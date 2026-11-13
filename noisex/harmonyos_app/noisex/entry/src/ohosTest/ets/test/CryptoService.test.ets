import { describe, beforeAll, beforeEach, afterEach, afterAll, it, expect } from '@ohos/hypium';
import { CryptoService } from '../../../main/ets/service/CryptoService';

export default function cryptoServiceTest() {
  describe('CryptoServiceTest', () => {
    const crypto: CryptoService = CryptoService.getInstance();

    beforeAll(() => {})
    beforeEach(() => {})
    afterEach(() => {
      crypto.clearRoomKey('test-room-a');
      crypto.clearRoomKey('test-room-b');
      crypto.clearRoomKey('test-room-c');
    })
    afterAll(() => {})

    // 注意：曾经用 try{...}catch(e){expect(true).assertTrue()} 包裹，会吞掉 HKDF 抛出的
    // 'Unsupported HMAC algorithm' 异常导致测试"假通过"，掩盖 CryptoService deriveAesKey 的
    // 算法名 bug 数月。现已移除吞异常包裹，让失败真实暴露。
    it('encrypt_decrypt_roundtrip_shouldReturnOriginal', 0, async () => {
      const roomIdA: string = 'test-room-a';
      const roomIdB: string = 'test-room-b';

      const pubKeyA: string = await crypto.generateKeyPair(roomIdA);
      const pubKeyB: string = await crypto.generateKeyPair(roomIdB);
      expect(pubKeyA.length > 0).assertTrue();
      expect(pubKeyB.length > 0).assertTrue();

      const derivedA: boolean = await crypto.deriveSharedKey(roomIdA, pubKeyB);
      const derivedB: boolean = await crypto.deriveSharedKey(roomIdB, pubKeyA);
      expect(derivedA).assertTrue();
      expect(derivedB).assertTrue();

      const plaintext: string = 'Hello, NoiseX!';
      const ciphertext: string = await crypto.encrypt(roomIdA, plaintext);
      expect(ciphertext !== plaintext).assertTrue();

      const decrypted: string = await crypto.decrypt(roomIdB, ciphertext);
      expect(decrypted).assertEqual(plaintext);

      crypto.clearRoomKey(roomIdA);
      crypto.clearRoomKey(roomIdB);
    })

    it('encrypt_nullKey_shouldReturnPlaintext', 0, async () => {
      const roomId: string = 'test-room-c';
      const plaintext: string = 'no-key-message';
      expect(crypto.hasSharedKey(roomId)).assertFalse();
      const encrypted: string = await crypto.encrypt(roomId, plaintext);
      expect(encrypted).assertEqual(plaintext);
      const decrypted: string = await crypto.decrypt(roomId, 'ciphertext-b64');
      expect(decrypted).assertEqual('ciphertext-b64');
    })

    it('hasSharedKey_afterKeyExchange_shouldReturnTrue', 0, async () => {
      const roomIdA: string = 'test-room-a';
      const roomIdB: string = 'test-room-b';

      const pubKeyA: string = await crypto.generateKeyPair(roomIdA);
      const pubKeyB: string = await crypto.generateKeyPair(roomIdB);
      expect(pubKeyA.length > 0).assertTrue();

      const derived: boolean = await crypto.deriveSharedKey(roomIdA, pubKeyB);
      expect(derived).assertTrue();
      expect(crypto.hasSharedKey(roomIdA)).assertTrue();

      crypto.clearRoomKey(roomIdA);
      crypto.clearRoomKey(roomIdB);
    })

    it('clearRoomKey_afterClear_shouldReturnFalse', 0, async () => {
      const roomId: string = 'test-room-c';
      crypto.clearRoomKey(roomId);
      expect(crypto.hasSharedKey(roomId)).assertFalse();

      const roomIdA: string = 'test-room-a';
      const roomIdB: string = 'test-room-b';

      const pubKeyA: string = await crypto.generateKeyPair(roomIdA);
      const pubKeyB: string = await crypto.generateKeyPair(roomIdB);
      await crypto.deriveSharedKey(roomIdA, pubKeyB);
      expect(crypto.hasSharedKey(roomIdA)).assertTrue();

      crypto.clearRoomKey(roomIdA);
      expect(crypto.hasSharedKey(roomIdA)).assertFalse();

      crypto.clearRoomKey(roomIdB);
    })
  })
}
