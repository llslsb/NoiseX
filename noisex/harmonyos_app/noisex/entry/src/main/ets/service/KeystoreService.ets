import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { huks } from '@kit.UniversalKeystoreKit';
import { util } from '@kit.ArkTS';
import { Logger } from '../common/Logger';

/** v2 信封：{"v":2,"iv":<b64>,"ct":<b64>}（与 Flutter 端 KeystoreService 单源同款格式） */
interface KeystoreEnvelope {
  v: number;
  iv: string;
  ct: string;
}

// 硬件密钥库包裹服务：主密钥由 HUKS 生成保护、不可导出，明文密钥永不落盘。
// 会话流程对齐官方 huks 加解密示例（AES/GCM/NoPadding）：
// 加密 outData = 密文||tag（末 16 字节），解密以 HUKS_TAG_AE_TAG 传 tag。
// 包裹/解开失败（主密钥被清、密文被篡改）返回 null，调用方必须跳过落盘
// ——宁可不落盘（牺牲重启后的解密连续性），也绝不降级为明文写入。
export class KeystoreService {
  private static instance: KeystoreService;

  private constructor() {}

  public static getInstance(): KeystoreService {
    if (!KeystoreService.instance) {
      KeystoreService.instance = new KeystoreService();
    }
    return KeystoreService.instance;
  }

  // 包裹明文 JSON → v2 信封字符串；失败返回 null
  public async wrapJson(plain: string): Promise<string | null> {
    try {
      await this.ensureMasterKey();
      const nonce: Uint8Array = this.randomBytes(12);
      const out: Uint8Array | null = await this.gcmSession(
        huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_ENCRYPT, nonce, null,
        this.textEncode(plain));
      if (out === null || out.length < 16) {
        return null;
      }
      const base64: util.Base64Helper = new util.Base64Helper();
      const envelope: KeystoreEnvelope = {
        v: 2,
        iv: base64.encodeToStringSync(nonce),
        ct: base64.encodeToStringSync(out)
      };
      return JSON.stringify(envelope);
    } catch (e) {
      Logger.error(`[KeystoreService] Wrap failed: ${e}`);
      return null;
    }
  }

  // 解开 v2 信封 → 明文 JSON；失败（主密钥被清 / 密文被篡改）返回 null
  public async unwrapJson(blob: string): Promise<string | null> {
    try {
      const parsed: ESObject = JSON.parse(blob) as ESObject;
      const ivStr: string = parsed['iv'] as string;
      const ctStr: string = parsed['ct'] as string;
      if (typeof ivStr !== 'string' || typeof ctStr !== 'string') {
        return null;
      }
      const base64: util.Base64Helper = new util.Base64Helper();
      const nonce: Uint8Array = base64.decodeSync(ivStr);
      const combined: Uint8Array = base64.decodeSync(ctStr);
      if (nonce.length !== 12 || combined.length < 16) {
        return null;
      }
      const tag: Uint8Array = combined.slice(combined.length - 16);
      const ctOnly: Uint8Array = combined.slice(0, combined.length - 16);
      await this.ensureMasterKey();
      const out: Uint8Array | null = await this.gcmSession(
        huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_DECRYPT, nonce, tag, ctOnly);
      if (out === null) {
        return null;
      }
      return this.textDecode(out);
    } catch (e) {
      Logger.error(`[KeystoreService] Unwrap failed: ${e}`);
      return null;
    }
  }

  private async gcmSession(purpose: huks.HuksKeyPurpose, nonce: Uint8Array,
    tag: Uint8Array | null, inData: Uint8Array): Promise<Uint8Array | null> {
    const props: huks.HuksParam[] = [
      { tag: huks.HuksTag.HUKS_TAG_ALGORITHM, value: huks.HuksKeyAlg.HUKS_ALG_AES },
      { tag: huks.HuksTag.HUKS_TAG_KEY_SIZE, value: huks.HuksKeySize.HUKS_AES_KEY_SIZE_256 },
      { tag: huks.HuksTag.HUKS_TAG_PURPOSE, value: purpose },
      { tag: huks.HuksTag.HUKS_TAG_PADDING, value: huks.HuksKeyPadding.HUKS_PADDING_NONE },
      { tag: huks.HuksTag.HUKS_TAG_BLOCK_MODE, value: huks.HuksCipherMode.HUKS_MODE_GCM },
      { tag: huks.HuksTag.HUKS_TAG_NONCE, value: nonce }
    ];
    if (tag !== null) {
      const tagParam: huks.HuksParam =
        { tag: huks.HuksTag.HUKS_TAG_AE_TAG, value: tag };
      props.push(tagParam);
    }
    const options: huks.HuksOptions = { properties: props, inData: inData };
    const initResult = await huks.initSession('noisex_e2ee_master', options);
    const finishResult = await huks.finishSession(initResult.handle, options);
    return finishResult.outData as Uint8Array;
  }

  private async ensureMasterKey(): Promise<void> {
    try {
      const exist: boolean =
        await huks.isKeyItemExist('noisex_e2ee_master', { properties: [] });
      if (exist) {
        return;
      }
    } catch (_) {
      // 查询失败不阻断，继续尝试生成（已存在时生成会失败，由后续会话验证）
    }
    const genProps: huks.HuksParam[] = [
      { tag: huks.HuksTag.HUKS_TAG_ALGORITHM, value: huks.HuksKeyAlg.HUKS_ALG_AES },
      { tag: huks.HuksTag.HUKS_TAG_KEY_SIZE, value: huks.HuksKeySize.HUKS_AES_KEY_SIZE_256 },
      {
        tag: huks.HuksTag.HUKS_TAG_PURPOSE,
        value: huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_ENCRYPT |
          huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_DECRYPT
      }
    ];
    try {
      await huks.generateKeyItem('noisex_e2ee_master', { properties: genProps });
    } catch (_) {
      // 已存在（或设备不支持）：由后续加解密会话给出最终结论
    }
  }

  private randomBytes(len: number): Uint8Array {
    const rand: cryptoFramework.Random = cryptoFramework.createRandom();
    return rand.generateRandomSync(len).data;
  }

  private textEncode(str: string): Uint8Array {
    const encoder: util.TextEncoder = new util.TextEncoder();
    return encoder.encodeInto(str);
  }

  private textDecode(bytes: Uint8Array): string {
    const decoder: util.TextDecoder = new util.TextDecoder('utf-8');
    return decoder.decodeToString(bytes);
  }
}
