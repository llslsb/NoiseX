import { describe, beforeAll, afterAll, it, expect } from '@ohos/hypium';
import { WsService } from '../../../main/ets/service/WsService';
import { AuthService } from '../../../main/ets/service/AuthService';
import { Constants } from '../../../main/ets/model/Constants';

// WsService 重连链回归测试（9f96bba 修复）。
// 背景：修复前 error 事件与 connect 回调失败路径均不调度重连，首次连接失败后
// 重连链永久断裂，客户端停在"正在重连"。本测试将 WS 指向不可达地址（本机保留
// 端口 9，立即拒绝），断言重连计数持续增长——若回归，attempt 增量停在 0。
const UNREACHABLE_WS: string = 'ws://127.0.0.1:9/ws';

function sleep(ms: number): Promise<void> {
  return new Promise<void>((resolve) => {
    setTimeout(resolve, ms);
  });
}

export default function wsReconnectTest() {
  describe('WsServiceReconnectTest', () => {
    const ws: WsService = WsService.getInstance();
    let savedUrl: string | undefined = undefined;
    let savedToken: string = '';

    beforeAll(() => {
      savedUrl = AppStorage.get<string>('wsUrl');
      savedToken = AuthService.getInstance().getToken();
      AppStorage.setOrCreate('wsUrl', UNREACHABLE_WS);
      AuthService.getInstance().setToken('test-jwt-reconnect-only');
      ws.disconnect();
    });

    afterAll(() => {
      ws.disconnect();
      AppStorage.setOrCreate('wsUrl', savedUrl !== undefined ? savedUrl : Constants.DEFAULT_WS_URL);
      AuthService.getInstance().setToken(savedToken);
    });

    it('computeReconnectDelay_exponentialBackoffCapped', 0, () => {
      expect(WsService.computeReconnectDelay(0)).assertEqual(1000);
      expect(WsService.computeReconnectDelay(1)).assertEqual(2000);
      expect(WsService.computeReconnectDelay(2)).assertEqual(4000);
      expect(WsService.computeReconnectDelay(3)).assertEqual(8000);
      expect(WsService.computeReconnectDelay(4)).assertEqual(16000);
      expect(WsService.computeReconnectDelay(5)).assertEqual(30000);
      expect(WsService.computeReconnectDelay(10)).assertEqual(30000);
    });

    it('connectUnreachable_shouldKeepReconnectChainGrowing', 0, async () => {
      ws.disconnect();
      const before: number = ws.getReconnectAttempts();
      ws.connect();
      // 退避 1s→2s：4.5 秒内至少应完成 2 次失败重连调度
      await sleep(4500);
      ws.disconnect();
      expect(ws.getReconnectAttempts() - before).assertLarger(1);
    });

    it('intentionalDisconnect_shouldStopReconnectChain', 0, async () => {
      ws.disconnect();
      ws.connect();
      await sleep(300);
      ws.disconnect();
      const atStop: number = ws.getReconnectAttempts();
      // 主动断开后，原定 1s 后的下一次重连必须被取消
      await sleep(2500);
      expect(ws.getReconnectAttempts()).assertEqual(atStop);
    });
  });
}
