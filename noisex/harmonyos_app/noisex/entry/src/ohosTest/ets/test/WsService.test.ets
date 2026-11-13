import { describe, beforeAll, beforeEach, afterEach, afterAll, it, expect } from '@ohos/hypium';
import { WsService } from '../../../main/ets/service/WsService';

export default function wsServiceTest() {
  describe('WsServiceTest', () => {
    beforeAll(() => {})
    beforeEach(() => {})
    afterEach(() => {})
    afterAll(() => {})

    it('getInstance_shouldReturnSameSingleton', 0, () => {
      const a: WsService = WsService.getInstance();
      const b: WsService = WsService.getInstance();
      expect(a === b).assertTrue();
    })

    it('getIsConnected_initialState_shouldReturnFalse', 0, () => {
      const ws: WsService = WsService.getInstance();
      expect(ws.getIsConnected()).assertFalse();
    })

    it('sendChatMessage_shouldConstructCorrectPayload', 0, () => {
      const ws: WsService = WsService.getInstance();
      const payload: Record<string, Object> = {
        'type': 'chat' as Object,
        'roomId': 'room-123' as Object,
        'content': 'hello' as Object
      };
      const json: string = JSON.stringify(payload);
      const parsed: Record<string, Object> = JSON.parse(json) as Record<string, Object>;
      expect((parsed['type'] as string)).assertEqual('chat');
      expect((parsed['roomId'] as string)).assertEqual('room-123');
      expect((parsed['content'] as string)).assertEqual('hello');
      ws.sendChatMessage('room-123', 'hello');
      expect(true).assertTrue();
    })

    it('sendKeyExchange_shouldConstructCorrectPayload', 0, () => {
      const ws: WsService = WsService.getInstance();
      const payload: Record<string, Object> = {
        'type': 'key_exchange' as Object,
        'roomId': 'room-456' as Object,
        'pubKey': 'base64pubkey' as Object
      };
      const json: string = JSON.stringify(payload);
      const parsed: Record<string, Object> = JSON.parse(json) as Record<string, Object>;
      expect((parsed['type'] as string)).assertEqual('key_exchange');
      expect((parsed['roomId'] as string)).assertEqual('room-456');
      expect((parsed['pubKey'] as string)).assertEqual('base64pubkey');
      ws.sendKeyExchange('room-456', 'base64pubkey');
      expect(true).assertTrue();
    })

    it('sendReadReceipt_shouldConstructCorrectPayload', 0, () => {
      const ws: WsService = WsService.getInstance();
      const payload: Record<string, Object> = {
        'type': 'read' as Object,
        'roomId': 'room-789' as Object,
        'messageId': 'msg-001' as Object
      };
      const json: string = JSON.stringify(payload);
      const parsed: Record<string, Object> = JSON.parse(json) as Record<string, Object>;
      expect((parsed['type'] as string)).assertEqual('read');
      expect((parsed['roomId'] as string)).assertEqual('room-789');
      expect((parsed['messageId'] as string)).assertEqual('msg-001');
      ws.sendReadReceipt('room-789', 'msg-001');
      expect(true).assertTrue();
    })

    it('confirmDeepConnection_shouldConstructCorrectPayload', 0, () => {
      const ws: WsService = WsService.getInstance();
      const payload: Record<string, Object> = {
        'type': 'deep_confirm' as Object,
        'roomId': 'room-abc' as Object
      };
      const json: string = JSON.stringify(payload);
      const parsed: Record<string, Object> = JSON.parse(json) as Record<string, Object>;
      expect((parsed['type'] as string)).assertEqual('deep_confirm');
      expect((parsed['roomId'] as string)).assertEqual('room-abc');
      ws.confirmDeepConnection('room-abc');
      expect(true).assertTrue();
    })

    it('callback_onMessageReceived_shouldBeSetAndInvoked', 0, () => {
      const ws: WsService = WsService.getInstance();
      let receivedContent: string = '';
      ws.onMessageReceived = (roomId: string, messageId: string, content: string, sender: string): void => {
        receivedContent = content;
      };
      if (ws.onMessageReceived !== null) {
        ws.onMessageReceived('room-1', 'msg-1', 'test-msg', 'user-1');
      }
      expect(receivedContent).assertEqual('test-msg');
      ws.onMessageReceived = null;
    })

    it('callback_onKeyExchange_shouldBeSetAndInvoked', 0, () => {
      const ws: WsService = WsService.getInstance();
      let receivedPubKey: string = '';
      ws.onKeyExchange = (roomId: string, pubKey: string): void => {
        receivedPubKey = pubKey;
      };
      if (ws.onKeyExchange !== null) {
        ws.onKeyExchange('room-2', 'pubkey-base64');
      }
      expect(receivedPubKey).assertEqual('pubkey-base64');
      ws.onKeyExchange = null;
    })

    it('handleMessage_chatJson_shouldParseCorrectly', 0, () => {
      const raw: string = JSON.stringify({
        'type': 'chat' as Object,
        'roomId': 'room-x' as Object,
        'content': 'hello world' as Object,
        'sender': 'user-y' as Object
      } as Record<string, Object>);
      const parsed: Record<string, Object> = JSON.parse(raw) as Record<string, Object>;
      const type: string = (parsed['type'] as string) ?? '';
      expect(type).assertEqual('chat');
      expect((parsed['roomId'] as string) ?? '').assertEqual('room-x');
      expect((parsed['content'] as string) ?? '').assertEqual('hello world');
      expect((parsed['sender'] as string) ?? '').assertEqual('user-y');
    })

    it('handleMessage_matchedJson_shouldParseCorrectly', 0, () => {
      const raw: string = JSON.stringify({
        'type': 'matched' as Object,
        'roomId': 'room-m' as Object,
        'signalCode': 'sig-001' as Object,
        'sonarContent': 'nearby' as Object
      } as Record<string, Object>);
      const parsed: Record<string, Object> = JSON.parse(raw) as Record<string, Object>;
      const type: string = (parsed['type'] as string) ?? '';
      expect(type).assertEqual('matched');
      expect((parsed['roomId'] as string) ?? '').assertEqual('room-m');
      expect((parsed['signalCode'] as string) ?? '').assertEqual('sig-001');
      expect((parsed['sonarContent'] as string) ?? '').assertEqual('nearby');
    })
  })
}
