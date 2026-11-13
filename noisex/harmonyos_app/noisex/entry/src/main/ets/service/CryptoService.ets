import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { Logger } from '../common/Logger';
import { util } from '@kit.ArkTS';
import { StorageService } from './StorageService';
import { KeystoreService } from './KeystoreService';

/** 密钥信封条目：k = Base64(raw key)，t = 最后确认活跃的 epoch 毫秒 */
interface KeyEnvelope {
  k: string;
  t: number;
}

/** 落盘信封加载结果：needsRewrite = v1 明文需迁移重写为 v2 */
interface LoadedEnvelope {
  envelope: Record<string, KeyEnvelope>;
  needsRewrite: boolean;
}

// 端到端加密服务 (ECDH + AES-256-GCM)
export class CryptoService {
  private static instance: CryptoService;
  // B18+：已派生共享密钥的应用内持久化键。存于应用私有 Preferences，不上传
  // 服务端；身份重置时随 clearAllKeys 一并清除。HUKS 硬件包裹已落地（v2）。
  //
  // 落盘格式（B18 时为明文 v1，现升级为硬件密钥库包裹的 v2）：
  // - v1（历史）：明文 JSON Map：roomId -> Base64(raw key)
  // - v2：{"v":2,"iv":<b64>,"ct":<b64>}，包裹明文为
  //   JSON Map：roomId -> {k: Base64(raw key), t: 最后确认活跃的 epoch 毫秒}
  // t 用于反追踪：距最后确认活跃超过 73h 的房间密钥在恢复时不再复活。
  private static readonly PERSISTED_KEYS_KEY: string = 'noisex_e2ee_keys';
  private static readonly PERSIST_VERSION: number = 2;
  // 房间密钥保留时间界：72h 房间寿命 + 1h 刷新宽限
  private static readonly KEY_RETENTION_MS: number = 73 * 3600 * 1000;
  // 活跃房间"最后确认时间"触碰节流
  private static readonly TOUCH_INTERVAL_MS: number = 3600 * 1000;
  // roomId -> 共享密钥 (AES-256)
  private sharedKeys: Map<string, cryptoFramework.SymKey> = new Map();
  // roomId -> 本方 ECDH 密钥对（临时，交换后可清除）
  private keyPairs: Map<string, cryptoFramework.KeyPair> = new Map();

  private constructor() {}

  public static getInstance(): CryptoService {
    if (!CryptoService.instance) {
      CryptoService.instance = new CryptoService();
    }
    return CryptoService.instance;
  }

  // 生成 ECDH 密钥对，返回 Base64 编码的公钥
  public async generateKeyPair(roomId: string): Promise<string> {
    try {
      const keyGen: cryptoFramework.AsyKeyGenerator =
        cryptoFramework.createAsyKeyGenerator('ECC256');
      const keyPair: cryptoFramework.KeyPair = await keyGen.generateKeyPair();
      this.keyPairs.set(roomId, keyPair);

      // 导出公钥为 Base64
      const pubKey: cryptoFramework.PubKey = keyPair.pubKey;
      const pubKeyEncoded: cryptoFramework.DataBlob = pubKey.getEncoded();
      const base64: util.Base64Helper = new util.Base64Helper();
      const pubKeyB64: string = base64.encodeToStringSync(pubKeyEncoded.data);
      return pubKeyB64;
    } catch (e) {
      Logger.error(`[CryptoService] Generate key pair failed: ${e}`);
      return '';
    }
  }

  // 收到对方公钥后，协商共享密钥
  public async deriveSharedKey(roomId: string, peerPubKeyB64: string): Promise<boolean> {
    try {
      const keyPair: cryptoFramework.KeyPair | undefined = this.keyPairs.get(roomId);
      if (keyPair === undefined) {
        Logger.error('[CryptoService] No key pair for room');
        return false;
      }

      // 解码对方公钥
      const base64: util.Base64Helper = new util.Base64Helper();
      const peerPubKeyBytes: Uint8Array = base64.decodeSync(peerPubKeyB64);
      const peerPubKeyBlob: cryptoFramework.DataBlob = { data: peerPubKeyBytes };

      const keyGen: cryptoFramework.AsyKeyGenerator =
        cryptoFramework.createAsyKeyGenerator('ECC256');
      const peerKeyPair: cryptoFramework.KeyPair =
        await keyGen.convertKey(peerPubKeyBlob, null);
      const peerPubKey: cryptoFramework.PubKey = peerKeyPair.pubKey;

      // ECDH 密钥协商
      const keyAgreement: cryptoFramework.KeyAgreement =
        cryptoFramework.createKeyAgreement('ECC256');
      const sharedSecret: cryptoFramework.DataBlob =
        await keyAgreement.generateSecret(keyPair.priKey, peerPubKey);

      // 从共享密钥派生 AES-256 密钥 (HKDF-Extract-Expand)
      const aesKeyBytes: Uint8Array = await this.deriveAesKey(sharedSecret.data);
      const aesKeyBlob: cryptoFramework.DataBlob = { data: aesKeyBytes };

      const symKeyGenerator: cryptoFramework.SymKeyGenerator =
        cryptoFramework.createSymKeyGenerator('AES256');
      const aesKey: cryptoFramework.SymKey = await symKeyGenerator.convertKey(aesKeyBlob);
      this.sharedKeys.set(roomId, aesKey);
      // B18：持久化共享密钥，App 重启后历史消息可解密、加密会话可续
      const keyEncoded: cryptoFramework.DataBlob = aesKey.getEncoded();
      const keyB64: util.Base64Helper = new util.Base64Helper();
      await this.persistKey(roomId, keyB64.encodeToStringSync(keyEncoded.data));

      // 清除临时密钥对
      this.keyPairs.delete(roomId);

      Logger.info(`[CryptoService] Shared key derived for room ${roomId}`);
      return true;
    } catch (e) {
      Logger.error(`[CryptoService] Derive shared key failed: ${e}`);
      return false;
    }
  }

  // AES-256-GCM 加密
  public async encrypt(roomId: string, plaintext: string): Promise<string> {
    try {
      const aesKey: cryptoFramework.SymKey | undefined = this.sharedKeys.get(roomId);
      if (aesKey === undefined) {
        // 无密钥则返回原文（未协商时降级为明文）
        return plaintext;
      }

      // GCM 是流模式、填充被忽略，但 createCipher 规格串只认 'PKCS7'；
      // 'NOPAD' 会被底层拒收（"create C cipher fail"）导致加密静默降级为明文
      const cipher: cryptoFramework.Cipher =
        cryptoFramework.createCipher('AES256|GCM|PKCS7');
      // 生成 12 字节随机 IV
      const iv: Uint8Array = this.randomBytes(12);
      const aad: Uint8Array = new Uint8Array(0);
      const params: cryptoFramework.GcmParamsSpec = {
        algName: 'GcmParamsSpec',
        iv: { data: iv },
        aad: { data: aad },
        authTag: { data: new Uint8Array(16) }
      };

      await cipher.init(cryptoFramework.CryptoMode.ENCRYPT_MODE, aesKey, params);

      const input: cryptoFramework.DataBlob = {
        data: this.textEncode(plaintext)
      };
      const encrypted: cryptoFramework.DataBlob = await cipher.doFinal(input);

      // 输出格式: Base64(iv + ciphertext + authTag)
      // authTag 在 GCM 模式下由 doFinal 返回的末尾 16 字节包含
      const combined: Uint8Array = this.concatArrays(iv, encrypted.data);
      const base64: util.Base64Helper = new util.Base64Helper();
      return base64.encodeToStringSync(combined);
    } catch (e) {
      Logger.error(`[CryptoService] Encrypt failed: ${e}`);
      return plaintext;
    }
  }

  // AES-256-GCM 解密
  public async decrypt(roomId: string, ciphertextB64: string): Promise<string> {
    try {
      const aesKey: cryptoFramework.SymKey | undefined = this.sharedKeys.get(roomId);
      if (aesKey === undefined) {
        return ciphertextB64;
      }

      if (ciphertextB64 === null || ciphertextB64 === undefined || ciphertextB64.length === 0) {
        return '';
      }

      const base64: util.Base64Helper = new util.Base64Helper();
      const combined: Uint8Array = base64.decodeSync(ciphertextB64);

      if (combined === null || combined === undefined || combined.length < 28) {
        return ciphertextB64;
      }

      const iv: Uint8Array = combined.slice(0, 12);
      const encrypted: Uint8Array = combined.slice(12);

      // 同 encrypt：GCM 规格串必须用 'PKCS7'，'NOPAD' 会被拒收
      const cipher: cryptoFramework.Cipher =
        cryptoFramework.createCipher('AES256|GCM|PKCS7');
      // GCM 解密需要 authTag (末尾 16 字节)
      const authTag: Uint8Array = encrypted.slice(encrypted.length - 16);
      const ciphertextOnly: Uint8Array = encrypted.slice(0, encrypted.length - 16);
      const params: cryptoFramework.GcmParamsSpec = {
        algName: 'GcmParamsSpec',
        iv: { data: iv },
        aad: { data: new Uint8Array(0) },
        authTag: { data: authTag }
      };

      await cipher.init(cryptoFramework.CryptoMode.DECRYPT_MODE, aesKey, params);

      const input: cryptoFramework.DataBlob = { data: ciphertextOnly };
      const decrypted: cryptoFramework.DataBlob = await cipher.doFinal(input);

      return this.textDecode(decrypted.data);
    } catch (e) {
      Logger.error(`[CryptoService] Decrypt failed: ${e}`);
      return ciphertextB64;
    }
  }

  // 是否已协商密钥
  public hasSharedKey(roomId: string): boolean {
    return this.sharedKeys.has(roomId);
  }

  // 是否存在临时 ECDH 密钥对（B18 重协商判断用）
  public hasKeyPair(roomId: string): boolean {
    return this.keyPairs.has(roomId);
  }

  // ============ B18：密钥持久化（v2 HUKS 硬件包裹） ============

  // 读取落盘密钥信封：roomId -> {k, t}。兼容 v1 明文（needsRewrite=true，
  // 调用方负责重写为 v2）与 v2 包裹信封。v2 硬件解密失败（主密钥被清 /
  // 密文被篡改）时丢弃落盘并返回空信封，绝不降级为明文；等待下一次协商重建。
  private async loadEnvelope(): Promise<LoadedEnvelope> {
    const raw: string = await StorageService.getInstance()
      .getPref(CryptoService.PERSISTED_KEYS_KEY, '');
    if (raw.length === 0) {
      const empty: LoadedEnvelope = { envelope: {}, needsRewrite: false };
      return empty;
    }
    try {
      const parsed: ESObject = JSON.parse(raw) as ESObject;
      if (typeof parsed === 'object' && parsed !== null
        && parsed['v'] === CryptoService.PERSIST_VERSION) {
        const plain: string | null = await KeystoreService.getInstance()
          .unwrapJson(raw);
        if (plain === null) {
          await StorageService.getInstance()
            .setPref(CryptoService.PERSISTED_KEYS_KEY, '');
          const empty: LoadedEnvelope = { envelope: {}, needsRewrite: false };
          return empty;
        }
        const inner: ESObject = JSON.parse(plain) as ESObject;
        const envelope: Record<string, KeyEnvelope> = {};
        const roomIds: string[] = Object.keys(inner);
        for (let i: number = 0; i < roomIds.length; i++) {
          const entry: KeyEnvelope = inner[roomIds[i]] as KeyEnvelope;
          if (entry === undefined || typeof entry.k !== 'string'
            || (entry.k as string).length === 0) {
            continue;
          }
          const normalized: KeyEnvelope = {
            k: entry.k as string,
            t: typeof entry.t === 'number' ? entry.t : 0
          };
          envelope[roomIds[i]] = normalized;
        }
        const loaded: LoadedEnvelope = { envelope: envelope, needsRewrite: false };
        return loaded;
      }
      if (typeof parsed === 'object' && parsed !== null) {
        // v1 明文信封：原地迁移为 v2（内层补 t = now，迁移后由时间界接管）
        const legacy: Record<string, string> = parsed as Record<string, string>;
        const now: number = Date.now();
        const envelope: Record<string, KeyEnvelope> = {};
        const roomIds: string[] = Object.keys(legacy);
        for (let i: number = 0; i < roomIds.length; i++) {
          const migrated: KeyEnvelope = { k: legacy[roomIds[i]], t: now };
          envelope[roomIds[i]] = migrated;
        }
        const migrated: LoadedEnvelope = { envelope: envelope, needsRewrite: true };
        return migrated;
      }
      const empty: LoadedEnvelope = { envelope: {}, needsRewrite: false };
      return empty;
    } catch (e) {
      // 持久化数据损坏时按空信封处理，等待下一次协商重建
      const empty: LoadedEnvelope = { envelope: {}, needsRewrite: false };
      return empty;
    }
  }

  // 包裹并落盘信封。硬件保护不可用时返回 false 且不写任何内容。
  private async writeEnvelope(envelope: Record<string, KeyEnvelope>): Promise<boolean> {
    const wrapped: string | null = await KeystoreService.getInstance()
      .wrapJson(JSON.stringify(envelope));
    if (wrapped === null) {
      return false;
    }
    await StorageService.getInstance()
      .setPref(CryptoService.PERSISTED_KEYS_KEY, wrapped);
    return true;
  }

  // B18：持久化共享密钥（v2 信封，应用私有 Preferences）
  private async persistKey(roomId: string, keyB64: string): Promise<void> {
    try {
      const loaded: LoadedEnvelope = await this.loadEnvelope();
      const entry: KeyEnvelope = { k: keyB64, t: Date.now() };
      loaded.envelope[roomId] = entry;
      await this.writeEnvelope(loaded.envelope);
    } catch (e) {
      Logger.error(`[CryptoService] Persist key failed: ${e}`);
    }
  }

  private async removePersistedKey(roomId: string): Promise<void> {
    try {
      const loaded: LoadedEnvelope = await this.loadEnvelope();
      if (loaded.envelope[roomId] === undefined) {
        return;
      }
      // ArkTS 禁用 delete 操作符：重建对象移除目标房间
      const next: Record<string, KeyEnvelope> = {};
      const keys: string[] = Object.keys(loaded.envelope);
      for (let i: number = 0; i < keys.length; i++) {
        if (keys[i] !== roomId) {
          next[keys[i]] = loaded.envelope[keys[i]];
        }
      }
      await this.writeEnvelope(next);
    } catch (e) {
      Logger.error(`[CryptoService] Remove persisted key failed: ${e}`);
    }
  }

  // 房间列表同步后的密钥治理（反追踪兜底，与 Flutter 端 retainPersistedKeysOnly
  // 单源同款）：列表非空时清除不在活跃集合中的房间密钥（覆盖离线过期/进程重启
  // 残留）；列表为空视为不可信，不动任何密钥（防服务端异常清空误伤），残留密钥
  // 由 restore 时的 73h 时间界兜底清除；活跃房间的 t 按节流阈值触碰。
  public retainKeysOnly(activeRoomIds: string[]): void {
    this.retainKeysOnlyAsync(activeRoomIds).catch((e: BusinessError): void => {
      Logger.error(`[CryptoService] Retain keys failed: ${e}`);
    });
  }

  private async retainKeysOnlyAsync(activeRoomIds: string[]): Promise<void> {
    const loaded: LoadedEnvelope = await this.loadEnvelope();
    const roomIds: string[] = Object.keys(loaded.envelope);
    if (roomIds.length === 0) {
      return;
    }
    const active: Set<string> = new Set<string>(activeRoomIds);
    const now: number = Date.now();
    let changed: boolean = loaded.needsRewrite;
    const next: Record<string, KeyEnvelope> = {};
    for (let i: number = 0; i < roomIds.length; i++) {
      const roomId: string = roomIds[i];
      const entry: KeyEnvelope = loaded.envelope[roomId];
      if (typeof entry.k !== 'string' || entry.k.length === 0) {
        changed = true; // 剔除损坏条目
        continue;
      }
      if (!active.has(roomId)) {
        if (active.size === 0) {
          next[roomId] = entry; // 空列表不删键
        } else {
          changed = true;
        }
        continue;
      }
      if (now - entry.t > CryptoService.TOUCH_INTERVAL_MS) {
        const touched: KeyEnvelope = { k: entry.k, t: now };
        next[roomId] = touched;
        changed = true;
        continue;
      }
      next[roomId] = entry;
    }
    if (!changed) {
      return;
    }
    await this.writeEnvelope(next);
  }

  // B18：启动时恢复持久化的共享密钥（仅写内存映射；日志不含密钥材料）。
  // 同时完成 v1→v2 迁移落盘，以及反追踪时间界清理：
  // 距最后确认活跃超过 73h 的房间密钥不复活（房间 72h 寿命必已过期）。
  public async restorePersistedKeys(): Promise<void> {
    const loaded: LoadedEnvelope = await this.loadEnvelope();
    const cutoff: number = Date.now() - CryptoService.KEY_RETENTION_MS;
    const roomIds: string[] = Object.keys(loaded.envelope);
    const base64: util.Base64Helper = new util.Base64Helper();
    let restored: number = 0;
    for (let i: number = 0; i < roomIds.length; i++) {
      const roomId: string = roomIds[i];
      if (this.sharedKeys.has(roomId)) {
        restored++;
        continue;
      }
      const entry: KeyEnvelope = loaded.envelope[roomId];
      if (entry.t > 0 && entry.t < cutoff) {
        continue;
      }
      try {
        const keyBytes: Uint8Array = base64.decodeSync(entry.k);
        if (keyBytes.length !== 32) {
          continue;
        }
        const symKeyGen: cryptoFramework.SymKeyGenerator =
          cryptoFramework.createSymKeyGenerator('AES256');
        const keyBlob: cryptoFramework.DataBlob = { data: keyBytes };
        const symKey: cryptoFramework.SymKey = await symKeyGen.convertKey(keyBlob);
        this.sharedKeys.set(roomId, symKey);
        restored++;
      } catch (e) {
        continue;
      }
    }
    if (restored > 0) {
      Logger.info(`[CryptoService] Restored ${restored} persisted keys`);
    }
    if (loaded.needsRewrite) {
      await this.writeEnvelope(loaded.envelope);
    }
  }

  // 清除房间密钥（房间过期/离开时调用）
  public clearRoomKey(roomId: string): void {
    this.sharedKeys.delete(roomId);
    this.keyPairs.delete(roomId);
    // 异步落盘，不阻塞调用方
    this.removePersistedKey(roomId);
  }

  // 清除所有密钥（身份重置时调用）
  public clearAllKeys(): void {
    this.sharedKeys.clear();
    this.keyPairs.clear();
    StorageService.getInstance()
      .setPref(CryptoService.PERSISTED_KEYS_KEY, '');
    Logger.info('[CryptoService] All keys cleared');
  }

  // HKDF-Extract-Expand: 从 ECDH 共享密钥派生 AES-256 密钥
  private async deriveAesKey(ikm: Uint8Array): Promise<Uint8Array> {
    try {
      const saltInput: Uint8Array = this.stringToBytes('noisex-e2ee-salt');
      const info: Uint8Array = this.stringToBytes('noisex-e2ee-key');

      const hash: cryptoFramework.Md = cryptoFramework.createMd('SHA256');
      await hash.update({ data: saltInput });
      const saltHash: cryptoFramework.DataBlob = await hash.digest();
      const salt: Uint8Array = saltHash.data;

      // HKDF-Extract：PRK = HMAC-SHA256(key=SHA256(salt), msg=IKM)
      // 注意：HarmonyOS CryptoArchitectureKit (API 12) 的算法名规范（见官方 crypto-compute-mac 文档）：
      //   - createMac 只填摘要算法 'SHA256'（HMAC 由 createMac 内部隐含，不再写 'HMAC|SHA256'）
      //   - createSymKeyGenerator 填 'HMAC'（接受任意长度密钥字节）
      // 旧的 'HMAC|SHA256' / 'HMAC|SHA256|256' 会被 HCF 拒收（"Unsupported HMAC algorithm"），
      // 导致 HKDF 永远失败、sharedKeys 永不入库、key_exchange 无限回声。
      const hmacExtract: cryptoFramework.Mac = cryptoFramework.createMac('SHA256');
      const symKeyGenerator: cryptoFramework.SymKeyGenerator =
        cryptoFramework.createSymKeyGenerator('HMAC');
      const saltBlob: cryptoFramework.DataBlob = { data: salt };
      const saltKey: cryptoFramework.SymKey = await symKeyGenerator.convertKey(saltBlob);
      await hmacExtract.init(saltKey);
      const ikmBlob: cryptoFramework.DataBlob = { data: ikm };
      // update 是异步方法，必须 await：否则线程池繁忙时 doFinal 可能越过 update 执行，
      // PRK 变成对空消息的 HMAC，两端派生出不同密钥（GCM 认证失败、E2EE 间歇性失效）
      await hmacExtract.update(ikmBlob);
      const prkResult: cryptoFramework.DataBlob = await hmacExtract.doFinal();
      const prk: Uint8Array = prkResult.data;

      // HKDF-Expand：T(1) = HMAC-SHA256(key=PRK, msg=info || 0x01)
      const hmacExpand: cryptoFramework.Mac = cryptoFramework.createMac('SHA256');
      const prkKeyGen: cryptoFramework.SymKeyGenerator =
        cryptoFramework.createSymKeyGenerator('HMAC');
      const prkBlob: cryptoFramework.DataBlob = { data: prk };
      const prkKey: cryptoFramework.SymKey = await prkKeyGen.convertKey(prkBlob);
      await hmacExpand.init(prkKey);
      const infoBlob: cryptoFramework.DataBlob = { data: info };
      await hmacExpand.update(infoBlob);
      const oneByte: Uint8Array = new Uint8Array([0x01]);
      const oneBlob: cryptoFramework.DataBlob = { data: oneByte };
      await hmacExpand.update(oneBlob);
      const t1Result: cryptoFramework.DataBlob = await hmacExpand.doFinal();

      const key: Uint8Array = t1Result.data.slice(0, 32);
      return key;
    } catch (e) {
      Logger.error(`[CryptoService] Derive AES key failed: ${e}`);
      throw new Error(`Derive AES key failed: ${e}`);
    }
  }

  // 生成随机字节 (CSPRNG)
  private async randomBytesAsync(length: number): Promise<Uint8Array> {
    try {
      const random: cryptoFramework.Random = cryptoFramework.createRandom();
      const blob: cryptoFramework.DataBlob = await random.generateRandom(length);
      return blob.data;
    } catch (e) {
      Logger.error(`[CryptoService] CSPRNG failed, fallback: ${e}`);
      const fallback: Uint8Array = new Uint8Array(length);
      for (let i: number = 0; i < length; i++) {
        fallback[i] = Math.floor(Math.random() * 256);
      }
      return fallback;
    }
  }

  // 生成随机字节（同步版本，供 encrypt/decrypt 使用）
  private randomBytes(length: number): Uint8Array {
    try {
      const random: cryptoFramework.Random = cryptoFramework.createRandom();
      const blob: cryptoFramework.DataBlob = random.generateRandomSync(length);
      return blob.data;
    } catch (e) {
      Logger.error(`[CryptoService] CSPRNG sync failed, fallback: ${e}`);
      const fallback: Uint8Array = new Uint8Array(length);
      for (let i: number = 0; i < length; i++) {
        fallback[i] = Math.floor(Math.random() * 256);
      }
      return fallback;
    }
  }

  // 拼接 Uint8Array
  private concatArrays(a: Uint8Array, b: Uint8Array): Uint8Array {
    const result: Uint8Array = new Uint8Array(a.length + b.length);
    result.set(a, 0);
    result.set(b, a.length);
    return result;
  }

  // UTF-8 编码: string → Uint8Array (支持中文等多字节字符)
  private textEncode(str: string): Uint8Array {
    const encoder: util.TextEncoder = new util.TextEncoder();
    return encoder.encodeInto(str);
  }

  // UTF-8 解码: Uint8Array → string (支持中文等多字节字符)
  private textDecode(bytes: Uint8Array): string {
    const decoder: util.TextDecoder = new util.TextDecoder('utf-8');
    return decoder.decodeToString(bytes);
  }

  // 字符串转 Uint8Array (UTF-8 编码，用于 HKDF salt/info)
  private stringToBytes(str: string): Uint8Array {
    return this.textEncode(str);
  }
}
