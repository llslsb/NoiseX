package com.llslsb.noisex

import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/// 硬件密钥库桥（通道名与 lib/services/keystore_service.dart 单源同款，勿单边改）：
/// 主密钥由 AndroidKeyStore 生成、TEE 保护且不可导出，Dart 侧仅经此通道
/// 触发对 E2EE 密钥信封的加解密，明文密钥不跨进程。
class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, KEYSTORE_CHANNEL)
            .setMethodCallHandler { call, result ->
                if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
                    result.error("unsupported", "AndroidKeyStore requires API 23+", null)
                    return@setMethodCallHandler
                }
                try {
                    when (call.method) {
                        "encrypt" -> {
                            val plain = call.argument<String>("plain") ?: ""
                            val out = KeystoreBridge.encrypt(plain.toByteArray(Charsets.UTF_8))
                            result.success(mapOf("iv" to out.first, "ct" to out.second))
                        }
                        "decrypt" -> {
                            val iv = Base64.decode(call.argument<String>("iv") ?: "", Base64.NO_WRAP)
                            val ct = Base64.decode(call.argument<String>("ct") ?: "", Base64.NO_WRAP)
                            result.success(KeystoreBridge.decrypt(iv, ct).toString(Charsets.UTF_8))
                        }
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    // 不向 Dart 侧暴露异常细节（安全红线：错误不泄漏堆栈）
                    result.error("keystore_error", e.javaClass.simpleName, null)
                }
            }
    }

    companion object {
        const val KEYSTORE_CHANNEL = "noisex/keystore"
    }
}

/// AndroidKeyStore AES-256-GCM 包裹器：密文格式 ct||tag，与 HUKS 端约定一致。
private object KeystoreBridge {
    private const val ANDROID_KEYSTORE = "AndroidKeyStore"
    private const val MASTER_ALIAS = "noisex_e2ee_master"
    private const val GCM_TAG_BITS = 128

    private fun masterKey(): SecretKey {
        val keyStore = KeyStore.getInstance(ANDROID_KEYSTORE).apply { load(null) }
        (keyStore.getEntry(MASTER_ALIAS, null) as? KeyStore.SecretKeyEntry)?.let {
            return it.secretKey
        }
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, ANDROID_KEYSTORE)
        generator.init(
            KeyGenParameterSpec.Builder(
                MASTER_ALIAS,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .setRandomizedEncryptionRequired(true)
                .build()
        )
        return generator.generateKey()
    }

    fun encrypt(plain: ByteArray): Pair<String, String> {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, masterKey())
        val iv = cipher.iv
        val ctWithTag = cipher.doFinal(plain)
        return Base64.encodeToString(iv, Base64.NO_WRAP) to
            Base64.encodeToString(ctWithTag, Base64.NO_WRAP)
    }

    fun decrypt(iv: ByteArray, ctWithTag: ByteArray): ByteArray {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, masterKey(), GCMParameterSpec(GCM_TAG_BITS, iv))
        return cipher.doFinal(ctWithTag)
    }
}
