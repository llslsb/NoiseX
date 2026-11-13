import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noisex/services/location_service.dart';
import 'package:noisex/services/storage_service.dart';
import 'package:noisex/state/sonar_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 定位授权弹框路径守门测试（2026-11-06 用户实锤：重新开启收听又弹授权框）。
///
/// 定则：收听开关是纯标志位，授权框只允许由 getGeohash（启动时、发送声呐）触发。
/// 判据是原生桥的 ensureLocationPermission——它是鸿蒙端唯一会弹授权框的调用。
/// 测试环境没有 geolocator 插件，checkPermission 抛 MissingPluginException，
/// 走的正是鸿蒙端的原生桥分支。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('noisex/native_location');
  late List<String> calls;
  late bool granted;
  // 每次定位换一个纬度，避开 LocationService 单例里缓存的上一次网格
  var latitude = 20.0;

  setUp(() {
    calls = [];
    granted = true;
    LocationService().stopLocation();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      switch (call.method) {
        case 'checkLocationPermission':
        case 'ensureLocationPermission':
          return {'granted': granted};
        case 'getLocation':
          latitude += 1;
          return {'latitude': latitude, 'longitude': 117.0};
      }
      return null;
    });
  });

  tearDown(() {
    LocationService().stopLocation();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('startLocation（收听开关走的路径）永不弹授权框', () {
    test('已授权：只查授权后定位并回调网格', () async {
      String? changed;
      await LocationService().startLocation((geohash) => changed = geohash);

      expect(calls, equals(['checkLocationPermission', 'getLocation']));
      expect(changed, isNotNull);
      expect(LocationService().isRunning, isTrue);
    });

    test('未授权：安静返回，不定位、不弹框', () async {
      granted = false;
      String? changed;
      await LocationService().startLocation((geohash) => changed = geohash);

      expect(calls, equals(['checkLocationPermission']));
      expect(changed, isNull);
      expect(LocationService().isRunning, isFalse);
    });
  });

  group('getGeohash（启动时、发送声呐）才可以弹授权框', () {
    test('已授权：先走授权入口，再定位', () async {
      final geohash = await LocationService().getGeohash();

      expect(calls, equals(['ensureLocationPermission', 'getLocation']));
      expect(geohash, isNotEmpty);
    });

    test('用户拒绝：返回空网格，不定位', () async {
      granted = false;
      final geohash = await LocationService().getGeohash();

      expect(calls, equals(['ensureLocationPermission']));
      expect(geohash, isEmpty);
    });
  });

  group('收听开关是纯标志位', () {
    test('开和关都不碰定位与授权，只改状态并持久化', () async {
      SharedPreferences.setMockInitialValues({});
      await StorageService().init();
      final manager = SonarManager();
      addTearDown(manager.dispose);

      await manager.toggleListening(false);
      expect(manager.isListening, isFalse);

      await manager.toggleListening(true);
      expect(manager.isListening, isTrue);

      // 开关全程没有任何一次定位桥调用：不取定位，更不会弹授权框
      expect(calls, isEmpty);
    });
  });
}
