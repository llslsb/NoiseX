import { describe, beforeAll, beforeEach, afterEach, afterAll, it, expect } from '@ohos/hypium';
import { Constants } from '../main/ets/model/Constants';
import { MessageData } from '../main/ets/model/ApiTypes';
import { ChatRoom, applyServerSaveState, canRequestSaveConnection, canSaveConnection, canUnlockProfile, getDeepConnectionStatusText, getProfileButtonText, getProfileDisplayValue, getRoomCardRenderKey, getSaveConnectionStatusText, getUnreadMessageCount, normalizeProfileField, shouldFetchUnlockedProfile, shouldShowSaveConfirmedPrompt, isUnlockWindowAvailable, getUnlockWindowRemainingMs, setServerTimeOffset, getServerTimeOffset, getNow } from '../main/ets/model/ChatRoom';
import { shouldStartListening } from '../main/ets/model/ListeningRegistration';
import { Message, applyPeerReadReceipt, applyDeliveredReceipt, getMessageBubbleRenderKey, replaceLatestLocalMessageId, toLocalMessage } from '../main/ets/model/Message';
import { parsePeerLeftPayload, isPeerLeftValid, getPeerLeftNotificationBody } from '../main/ets/model/PeerLeftEvent';
import { getWitheringSecondaryText } from '../main/ets/service/RitualAnimationService';
import { ApiBusinessError, getFriendlyErrorMessage, mapApiErrorToFriendly } from '../main/ets/common/ApiErrorMessages';
import { createSonarInputTransitionState } from '../main/ets/model/SonarTransition';

export default function localUnitTest() {
  describe('localUnitTest', () => {
    // Defines a test suite. Two parameters are supported: test suite name and test suite function.
    beforeAll(() => {
      // Presets an action, which is performed only once before all test cases of the test suite start.
      // This API supports only one parameter: preset action function.
    });
    beforeEach(() => {
      // Presets an action, which is performed before each unit test case starts.
      // The number of execution times is the same as the number of test cases defined by **it**.
      // This API supports only one parameter: preset action function.
    });
    afterEach(() => {
      // Presets a clear action, which is performed after each unit test case ends.
      // The number of execution times is the same as the number of test cases defined by **it**.
      // This API supports only one parameter: clear action function.
    });
    afterAll(() => {
      // Presets a clear action, which is performed after all test cases of the test suite end.
      // This API supports only one parameter: clear action function.
    });
    it('assertContain', 0, () => {
      // Defines a test case. This API supports three parameters: test case name, filter parameter, and test case function.
      let a = 'abc';
      let b = 'b';
      // Defines a variety of assertion methods, which are used to declare expected boolean conditions.
      expect(a).assertContain(b);
      expect(a).assertEqual(a);
    });

    it('usesValidDefaultGeohashForSonarMatching', 0, () => {
      const geohash: string = Constants.DEFAULT_GEOHASH;
      expect(geohash.length).assertEqual(Constants.DEFAULT_GEOHASH_PRECISION);
      expect(/^[0-9b-hj-km-np-z]+$/.test(geohash)).assertTrue();
    });

    it('keepsOwnHistoryMessageUnreadUntilPeerReceiptArrives', 0, () => {
      const apiMessage: MessageData = {
        id: 'msg-1',
        sender: 'me',
        content: 'hello',
        timestamp: 1000
      };

      const localMessage = toLocalMessage(apiMessage, 'room-1', '');

      expect(localMessage.sender).assertEqual('me');
      expect(localMessage.read).assertFalse();
    });

    it('marksOwnHistoryMessageReadWhenPeerReceiptCoversIt', 0, () => {
      const apiMessage: MessageData = {
        id: 'msg-1',
        sender: 'me',
        content: 'hello',
        timestamp: 1000
      };

      const localMessage = toLocalMessage(apiMessage, 'room-1', 'msg-1');

      expect(localMessage.sender).assertEqual('me');
      expect(localMessage.read).assertTrue();
    });

    it('returnsZeroUnreadCountWhenOtherMessagesAreAlreadyRead', 0, () => {
      const messages: Message[] = [
        { id: 'msg-1', roomId: 'room-1', sender: 'other', content: 'hello', timestamp: 1000, read: false, encrypted: true }
      ];

      expect(getUnreadMessageCount(messages, 'msg-1')).assertEqual(0);
    });

    it('countsOnlyOtherMessagesAfterReadPointerAsUnread', 0, () => {
      const messages: Message[] = [
        { id: 'msg-1', roomId: 'room-1', sender: 'other', content: 'read', timestamp: 1000, read: false, encrypted: true },
        { id: 'msg-2', roomId: 'room-1', sender: 'me', content: 'mine', timestamp: 2000, read: false, encrypted: true },
        { id: 'msg-3', roomId: 'room-1', sender: 'other', content: 'unread', timestamp: 3000, read: false, encrypted: true }
      ];

      expect(getUnreadMessageCount(messages, 'msg-1')).assertEqual(1);
    });

    it('showsWaitingPeerConfirmAfterOwnDeepConfirm', 0, () => {
      expect(getDeepConnectionStatusText(false, false, false, false)).assertEqual('需双方各5条消息');
      expect(getDeepConnectionStatusText(true, false, false, false)).assertEqual('✓ 已达成，待确认');
      expect(getDeepConnectionStatusText(true, true, false, false)).assertEqual('✓ 已确认，等待对方');
      expect(getDeepConnectionStatusText(true, true, true, false)).assertEqual('✓ 双方已确认');
      expect(getDeepConnectionStatusText(true, true, true, true)).assertEqual('✓ 资料已解锁');
    });

    it('togglesProfileButtonTextByInfoPanelState', 0, () => {
      expect(getProfileButtonText(false)).assertEqual('查看资料');
      expect(getProfileButtonText(true)).assertEqual('收起资料');
    });

    it('showsSaveConnectionStatusTextByConfirmState', 0, () => {
      expect(getSaveConnectionStatusText(false, false)).assertEqual('保存连接');
      expect(getSaveConnectionStatusText(true, false)).assertEqual('等待对方确认');
      expect(getSaveConnectionStatusText(true, true)).assertEqual('连接已保存');
    });

    it('disablesSaveConnectionAfterCurrentUserConfirmed', 0, () => {
      expect(canSaveConnection(false, false)).assertTrue();
      expect(canSaveConnection(true, false)).assertFalse();
      expect(canSaveConnection(true, true)).assertFalse();
    });

    it('onlyAllowsUnlockRequestAfterBothDeepConfirmedInsideWindow', 0, () => {
      setServerTimeOffset(0);
      const createdAt: number = getNow() - 1000;

      expect(canUnlockProfile(false, false, true, createdAt)).assertFalse();
      expect(canUnlockProfile(true, false, true, createdAt)).assertFalse();
      expect(canUnlockProfile(false, true, true, createdAt)).assertTrue();
      expect(canUnlockProfile(false, true, false, createdAt)).assertFalse();
      expect(canUnlockProfile(false, true, true, getNow() - 25 * 3600 * 1000)).assertFalse();
    });

    it('onlyAllowsSaveRequestAfterProfileUnlocked', 0, () => {
      expect(canRequestSaveConnection(false, false, false)).assertFalse();
      expect(canRequestSaveConnection(true, false, false)).assertTrue();
      expect(canRequestSaveConnection(true, true, false)).assertFalse();
      expect(canRequestSaveConnection(true, false, true)).assertFalse();
    });

    it('usesServerSaveStateAsCurrentRoomAuthority', 0, () => {
      const room: ChatRoom = {
        id: 'room-2',
        sonarContent: 'new connection',
        signalCode: 'RX-0002',
        createdAt: 1000,
        expiresAt: 2000,
        messages: [],
        unlocked: false,
        deepConnectionAchieved: false,
        deepConnectionConfirmed: false,
        bothDeepConfirmed: false,
        saveConnectionConfirmed: true,
        bothSaveConfirmed: true,
        otherProfile: null,
        lastReadMessageId: '',
        peerReadMessageId: ''
      };

      applyServerSaveState(room, false, false);

      expect(room.saveConnectionConfirmed).assertFalse();
      expect(room.bothSaveConfirmed).assertFalse();
      expect(getSaveConnectionStatusText(room.saveConnectionConfirmed, room.bothSaveConfirmed)).assertEqual('保存连接');
    });

    it('mapsUnlockAndSaveBusinessErrorsToActionableMessages', 0, () => {
      expect(mapApiErrorToFriendly(40001, '尚未达到深度交流条件')).assertEqual('还没有达到解锁条件，请先完成深度交流');
      expect(mapApiErrorToFriendly(40001, '资料尚未解锁')).assertEqual('资料解锁后才能保存连接');
      expect(mapApiErrorToFriendly(40001, 'agree 不能为空')).assertEqual('请求参数有误');
    });

    it('showsSaveConfirmedPromptOnlyOnFirstTransition', 0, () => {
      expect(shouldShowSaveConfirmedPrompt(true, false)).assertTrue();
      expect(shouldShowSaveConfirmedPrompt(true, true)).assertFalse();
      expect(shouldShowSaveConfirmedPrompt(false, false)).assertFalse();
    });

    it('showsPlaceholderForEmptyProfileFields', 0, () => {
      expect(getProfileDisplayValue('')).assertEqual('未填写');
      expect(getProfileDisplayValue('广州')).assertEqual('广州');
    });

    it('normalizesNullableProfileFieldsBeforeDisplay', 0, () => {
      expect(normalizeProfileField(null)).assertEqual('');
      expect(normalizeProfileField(undefined)).assertEqual('');
      expect(normalizeProfileField('广州')).assertEqual('广州');
    });

    it('fetchesUnlockedProfileWhenRoomHasNoCachedProfile', 0, () => {
      expect(shouldFetchUnlockedProfile(true, false)).assertTrue();
      expect(shouldFetchUnlockedProfile(true, true)).assertFalse();
      expect(shouldFetchUnlockedProfile(false, false)).assertFalse();
    });

    it('changesRoomCardRenderKeyWhenReadPointerChanges', 0, () => {
      const room: ChatRoom = {
        id: 'room-1',
        sonarContent: 'hello',
        signalCode: 'RX-1234',
        createdAt: 1000,
        expiresAt: 2000,
        messages: [],
        unlocked: false,
        deepConnectionAchieved: false,
        deepConnectionConfirmed: false,
        bothDeepConfirmed: false,
        saveConnectionConfirmed: false,
        bothSaveConfirmed: false,
        otherProfile: null,
        lastReadMessageId: '',
        peerReadMessageId: ''
      };
      const unreadKey: string = getRoomCardRenderKey(room);

      room.lastReadMessageId = 'msg-1';

      expect(getRoomCardRenderKey(room) === unreadKey).assertFalse();
    });

    it('changesRoomCardRenderKeyWhenSaveStatusChanges', 0, () => {
      const room: ChatRoom = {
        id: 'room-1',
        sonarContent: 'hello',
        signalCode: 'RX-1234',
        createdAt: 1000,
        expiresAt: 2000,
        messages: [],
        unlocked: true,
        deepConnectionAchieved: true,
        deepConnectionConfirmed: true,
        bothDeepConfirmed: true,
        saveConnectionConfirmed: false,
        bothSaveConfirmed: false,
        otherProfile: null,
        lastReadMessageId: '',
        peerReadMessageId: ''
      };
      const beforeKey: string = getRoomCardRenderKey(room);

      room.saveConnectionConfirmed = true;

      expect(getRoomCardRenderKey(room) === beforeKey).assertFalse();
    });

    it('changesMessageBubbleRenderKeyWhenReadStateChanges', 0, () => {
      const message: Message = {
        id: 'msg-1',
        roomId: 'room-1',
        sender: 'me',
        content: 'hello',
        timestamp: 1000,
        read: false,
        encrypted: true
      };
      const unreadKey: string = getMessageBubbleRenderKey(message);

      message.read = true;

      expect(getMessageBubbleRenderKey(message) === unreadKey).assertFalse();
    });

    it('appliesPeerReadReceiptWithoutMutatingOriginalMessages', 0, () => {
      const messages: Message[] = [
        { id: 'msg-1', roomId: 'room-1', sender: 'me', content: 'mine', timestamp: 1000, read: false, encrypted: true },
        { id: 'msg-3', roomId: 'room-1', sender: 'me', content: 'mine later', timestamp: 3000, read: false, encrypted: true },
        { id: 'msg-2', roomId: 'room-1', sender: 'other', content: 'other', timestamp: 2000, read: false, encrypted: true }
      ];

      const updated: Message[] = applyPeerReadReceipt(messages, 'msg-1');

      expect(updated === messages).assertFalse();
      expect(messages[0].read).assertFalse();
      expect(messages[1].read).assertFalse();
      expect(updated[0].read).assertTrue();
      expect(updated[1].read).assertFalse();
      expect(updated[2].read).assertFalse();
    });

    it('replacesLatestLocalMessageIdSoReadReceiptCanUpdateOpenChat', 0, () => {
      const messages: Message[] = [
        { id: 'local-1700000000000-1234', roomId: 'room-1', sender: 'me', content: 'mine', timestamp: 1000, read: false, encrypted: true }
      ];

      const acked: Message[] = replaceLatestLocalMessageId(messages, '1700000001000-0');
      const read: Message[] = applyPeerReadReceipt(acked, '1700000001000-0');

      expect(acked === messages).assertFalse();
      expect(messages[0].id).assertEqual('local-1700000000000-1234');
      expect(acked[0].id).assertEqual('1700000001000-0');
      expect(read[0].read).assertTrue();
    });

    it('marksAckedLocalMessageEncryptedWhenServerAckDecrypts', 0, () => {
      const messages: Message[] = [
        { id: 'local-1700000000000-1234', roomId: 'room-1', sender: 'me', content: 'mine', timestamp: 1000, read: false, encrypted: false }
      ];

      const acked: Message[] = replaceLatestLocalMessageId(messages, '1700000001000-0', true);

      expect(acked[0].id).assertEqual('1700000001000-0');
      expect(acked[0].encrypted).assertTrue();
    });

    // P1-B：applyDeliveredReceipt 仅修改对应 me 消息的 delivered 标志
    it('applyDeliveredReceiptOnlyMarksMatchingMeMessage', 0, () => {
      const messages: Message[] = [
        { id: 'msg-1', roomId: 'room-1', sender: 'me', content: 'a', timestamp: 1000, read: false, encrypted: true },
        { id: 'msg-2', roomId: 'room-1', sender: 'other', content: 'b', timestamp: 2000, read: false, encrypted: true },
        { id: 'msg-3', roomId: 'room-1', sender: 'me', content: 'c', timestamp: 3000, read: false, encrypted: true }
      ];

      const updated: Message[] = applyDeliveredReceipt(messages, 'msg-1');

      expect(updated === messages).assertFalse();
      expect(updated[0].delivered === true).assertTrue();
      expect(updated[1].delivered === undefined).assertTrue();
      expect(updated[2].delivered === undefined).assertTrue();
    });

    // 已 read 的消息不应被 delivered 回退
    it('applyDeliveredReceiptDoesNotRegressReadMessage', 0, () => {
      const messages: Message[] = [
        { id: 'msg-1', roomId: 'room-1', sender: 'me', content: 'a', timestamp: 1000, read: true, encrypted: true }
      ];

      const updated: Message[] = applyDeliveredReceipt(messages, 'msg-1');

      // 应返回同一引用（未变更）
      expect(updated === messages).assertTrue();
      expect(updated[0].read).assertTrue();
    });

    it('forcesListeningRegistrationAfterWebSocketReconnect', 0, () => {
      expect(shouldStartListening('wts4n4', 'wts4n4', false)).assertFalse();
      expect(shouldStartListening('wts4n4', 'wts4n4', true)).assertTrue();
    });

    it('reportsUnlockWindowAvailableWhenWithin24Hours', 0, () => {
      const now: number = Date.now();
      // 创建于 1 小时前，窗口可用
      expect(isUnlockWindowAvailable(now - 3600000)).assertTrue();
      // 创建于 23 小时前，窗口可用
      expect(isUnlockWindowAvailable(now - 23 * 3600 * 1000)).assertTrue();
    });

    it('reportsUnlockWindowClosedWhenPast24Hours', 0, () => {
      const now: number = Date.now();
      // 创建于 25 小时前，窗口关闭
      expect(isUnlockWindowAvailable(now - 25 * 3600 * 1000)).assertFalse();
    });

    it('calculatesUnlockWindowRemainingMsCorrectly', 0, () => {
      const now: number = Date.now();
      const oneHourAgo: number = now - 3600000;
      const remaining: number = getUnlockWindowRemainingMs(oneHourAgo);
      // 剩余约 23 小时，允许 1 秒误差
      expect(remaining > 22 * 3600 * 1000).assertTrue();
      expect(remaining < 24 * 3600 * 1000).assertTrue();
    });

    it('returnsZeroRemainingWhenWindowExpired', 0, () => {
      const now: number = Date.now();
      const twoDaysAgo: number = now - 48 * 3600 * 1000;
      expect(getUnlockWindowRemainingMs(twoDaysAgo)).assertEqual(0);
    });

    it('adjustsCurrentTimeByServerOffset', 0, () => {
      // 设置偏移 +5 秒（服务端比本地快 5 秒）
      setServerTimeOffset(5000);
      expect(getServerTimeOffset()).assertEqual(5000);
      const localNow: number = Date.now();
      const serverNow: number = getNow();
      // serverNow 应比 localNow 大约大 5000ms（允许微小误差）
      expect(serverNow - localNow >= 4990).assertTrue();
      expect(serverNow - localNow <= 5010).assertTrue();
      // 重置偏移
      setServerTimeOffset(0);
      expect(getServerTimeOffset()).assertEqual(0);
    });

    it('defaultsToZeroOffsetWhenNotSynced', 0, () => {
      setServerTimeOffset(0);
      expect(getServerTimeOffset()).assertEqual(0);
      expect(getNow()).assertEqual(Date.now());
    });

    // F2-3/F2-4：peer_left payload 解析测试。
    // 关键回归：通知/Toast 文案不能渲染 undefined / null（用户反馈 bug）。
    it('parsesWellFormedPeerLeftPayload', 0, () => {
      const payload: Record<string, Object> = {
        'type': 'peer_left' as Object,
        'roomId': 'room-1' as Object,
        'signalCode': 'RX-1234' as Object,
        'leftAt': 1700000000000 as Object
      };
      const ev = parsePeerLeftPayload(payload);
      expect(ev.roomId).assertEqual('room-1');
      expect(ev.signalCode).assertEqual('RX-1234');
      expect(ev.leftAt).assertEqual(1700000000000);
      expect(isPeerLeftValid(ev)).assertTrue();
      expect(getPeerLeftNotificationBody(ev)).assertEqual('RX-1234 已离开对话');
    });

    it('fallsBackToCounterpartLabelWhenSignalCodeMissing', 0, () => {
      const payload: Record<string, Object> = {
        'type': 'peer_left' as Object,
        'roomId': 'room-1' as Object
      };
      const ev = parsePeerLeftPayload(payload);
      expect(ev.signalCode).assertEqual('对方');
      const body: string = getPeerLeftNotificationBody(ev);
      expect(body).assertEqual('对方 已离开对话');
      // 关键回归：文案永远不能包含 undefined / null
      expect(body.indexOf('undefined') < 0).assertTrue();
      expect(body.indexOf('null') < 0).assertTrue();
    });

    it('fallsBackToCounterpartLabelWhenSignalCodeEmpty', 0, () => {
      const payload: Record<string, Object> = {
        'roomId': 'room-1' as Object,
        'signalCode': '' as Object
      };
      const ev = parsePeerLeftPayload(payload);
      expect(ev.signalCode).assertEqual('对方');
      expect(getPeerLeftNotificationBody(ev)).assertEqual('对方 已离开对话');
    });

    it('marksPeerLeftInvalidWhenRoomIdMissing', 0, () => {
      const payload: Record<string, Object> = {
        'signalCode': 'RX-1' as Object
      };
      const ev = parsePeerLeftPayload(payload);
      expect(ev.roomId).assertEqual('');
      expect(isPeerLeftValid(ev)).assertFalse();
    });

    it('marksPeerLeftInvalidWhenRoomIdEmpty', 0, () => {
      const payload: Record<string, Object> = {
        'roomId': '' as Object,
        'signalCode': 'RX-1' as Object
      };
      const ev = parsePeerLeftPayload(payload);
      expect(isPeerLeftValid(ev)).assertFalse();
    });

    it('marksPeerLeftInvalidWhenRoomIdIsUndefinedLiteral', 0, () => {
      const payload: Record<string, Object> = {
        'roomId': 'undefined' as Object,
        'signalCode': 'RX-1' as Object
      };
      const ev = parsePeerLeftPayload(payload);
      expect(isPeerLeftValid(ev)).assertFalse();
    });

    it('witheringCopyNeverIncludesRoomIdShortCode', 0, () => {
      expect(getWitheringSecondaryText('room-abcdef')).assertEqual('信号已消散');
      expect(getWitheringSecondaryText('undefined')).assertEqual('信号已消散');
    });

    it('defaultsLeftAtToZeroWhenMissingOrWrongType', 0, () => {
      const missing = parsePeerLeftPayload({ 'roomId': 'r' as Object });
      const wrong = parsePeerLeftPayload({
        'roomId': 'r' as Object,
        'leftAt': 'not-a-number' as Object
      });
      expect(missing.leftAt).assertEqual(0);
      expect(wrong.leftAt).assertEqual(0);
    });

    it('mapsKnownApiErrorsToFriendlyChineseMessages', 0, () => {
      expect(mapApiErrorToFriendly(40301, 'RATE_LIMIT')).assertEqual('发送太频繁，请稍后再试');
      expect(mapApiErrorToFriendly(40101, 'TOKEN_EXPIRED')).assertEqual('登录已过期，请重启应用');
      expect(mapApiErrorToFriendly(40901, 'SONAR_EXPIRED')).assertEqual('声呐已过期，请重新发送');
      expect(mapApiErrorToFriendly(40902, 'ROOM_CLOSED')).assertEqual('聊天室已关闭');
      expect(mapApiErrorToFriendly(40401, 'NOT_FOUND')).assertEqual('未找到对应内容');
      expect(mapApiErrorToFriendly(50001, 'INTERNAL_ERROR')).assertEqual('服务器开小差了，请稍后再试');
    });

    it('mapsDuplicateBadRequestToFriendlyMessage', 0, () => {
      expect(mapApiErrorToFriendly(40001, '请勿重复发送')).assertEqual('请勿发送重复内容的声呐');
      expect(mapApiErrorToFriendly(40001, 'invalid input')).assertEqual('请求参数有误');
    });

    it('extractsFriendlyMessageFromApiBusinessError', 0, () => {
      const err: ApiBusinessError = new ApiBusinessError(40902, 'ROOM_CLOSED');
      expect(getFriendlyErrorMessage(err, '操作失败，请重试')).assertEqual('聊天室已关闭');
      expect(getFriendlyErrorMessage(new Error('Unlock profile failed'), '操作失败，请重试')).assertEqual('操作失败，请重试');
    });

    it('definesSonarInputTransitionAsBurstThenCardReveal', 0, () => {
      const hidden = createSonarInputTransitionState(false);
      const visible = createSonarInputTransitionState(true);

      expect(hidden.introVisible).assertFalse();
      expect(hidden.burstVisible).assertTrue();
      expect(hidden.inputScale < visible.inputScale).assertTrue();
      expect(hidden.inputTranslateY > visible.inputTranslateY).assertTrue();
      expect(hidden.ringOpacity > visible.ringOpacity).assertTrue();
      expect(visible.ringOpacity > 0).assertTrue();
      expect(hidden.ringScale < visible.ringScale).assertTrue();
    });
  });
}