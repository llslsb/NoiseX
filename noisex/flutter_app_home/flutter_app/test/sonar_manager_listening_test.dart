import 'package:flutter_test/flutter_test.dart';
import 'package:noisex/models/constants.dart';
import 'package:noisex/services/storage_service.dart';
import 'package:noisex/state/sonar_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 收听开关回归测试（2026-11-06 用户实锤 bug：收听模式关闭仍收到别人的脉冲）。
///
/// 服务端注销由 app.dart 负责（真机验证）；这里锁死客户端两条根因：
/// ① 开关必须持久化——旧版写死 true，重启即静默恢复收听；
/// ② 静默模式下刷新声呐列表必须直接清空返回——长连接推送/切 Tab/重连都会触发刷新。
void main() {
  Future<void> initPrefs(Map<String, Object> values) async {
    SharedPreferences.setMockInitialValues(values);
    await StorageService().init();
  }

  test('新装（无存储记录）默认开启收听', () async {
    await initPrefs({});
    expect(SonarManager().isListening, isTrue);
  });

  test('用户上次关闭了收听：重启后保持静默，不会自动恢复', () async {
    await initPrefs({Constants.prefsKeyListeningEnabled: false});
    expect(SonarManager().isListening, isFalse);
  });

  test('关闭收听会持久化，并清空本地登记格与声呐列表', () async {
    await initPrefs({});
    final manager = SonarManager();
    await manager.toggleListening(false);

    expect(manager.isListening, isFalse);
    expect(manager.listeningGeohash, isEmpty);
    expect(manager.receivedSonars, isEmpty);
    expect(
      StorageService()
          .getBool(Constants.prefsKeyListeningEnabled, defaultValue: true),
      isFalse,
    );
  });

  test('静默模式下刷新声呐列表：不请求服务端，列表保持为空', () async {
    await initPrefs({Constants.prefsKeyListeningEnabled: false});
    final manager = SonarManager();
    var notified = 0;
    manager.addListener(() => notified++);

    // 无闸门时这里会发起网络请求；有闸门则同步走完、列表为空、不打扰界面
    await manager.refreshReceivedSonars();

    expect(manager.receivedSonars, isEmpty);
    expect(notified, 0);
  });
}
