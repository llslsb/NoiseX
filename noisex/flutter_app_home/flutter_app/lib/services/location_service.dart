import 'dart:async';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';

import 'debug_log.dart';

class LocationService {
  static final LocationService _instance = LocationService._();
  factory LocationService() => _instance;
  LocationService._();

  // OHOS 定位桥：geolocator 无 ohos 平台实现（MissingPluginException），
  // 由 EntryAbility 侧 geoLocationManager 兜底（单源：EntryAbility.ets）
  static const MethodChannel _nativeLocation = MethodChannel(
    'noisex/native_location',
  );

  /// 经原生桥取一次定位（桥内只查不弹：未授权回错误）；桥不存在（Android/iOS）或失败返回 null
  Future<({double lat, double lon})?> _nativeLocationFix() async {
    try {
      final result = await _nativeLocation.invokeMethod('getLocation');
      return (
        lat: (result['latitude'] as num).toDouble(),
        lon: (result['longitude'] as num).toDouble(),
      );
    } catch (_) {
      return null;
    }
  }

  /// 原生桥查授权（只查不弹）；桥不存在或失败按未授权处理
  Future<bool> _nativeHasPermission() async {
    try {
      final result =
          await _nativeLocation.invokeMethod('checkLocationPermission');
      return result['granted'] == true;
    } catch (_) {
      return false;
    }
  }

  /// 原生桥补授权（缺失时弹一次系统授权框）；桥不存在或失败按未授权处理。
  /// 只有 [getGeohash] 可以调用，见其注释。
  Future<bool> _nativeEnsurePermission() async {
    try {
      final result =
          await _nativeLocation.invokeMethod('ensureLocationPermission');
      return result['granted'] == true;
    } catch (_) {
      return false;
    }
  }

  String _currentGeohash = '';
  StreamSubscription<Position>? _positionStream;
  bool _isRunning = false;

  // Android 定位设置：
  // - forceLocationManager 直走系统 LocationManager（LocationManagerClient），
  //   不依赖 GMS FusedLocationProviderClient（部分 GMS 模拟器/设备无位置同意时
  //   永不回包，2026-11-05 familyrecipe_test 实锤：getCurrentPosition 挂死
  //   5 分钟+）。注意 API31+ LocationManagerClient 自身也优先请求框架 fused
  //   provider——模拟器上"位置注入"用 test-provider 名 fused 才能送达。
  //   AndroidSettings 对 iOS/OHOS 无副作用（OHOS 在 checkPermission 即抛
  //   MissingPluginException 走原生桥兜底），故无条件使用。
  // - timeLimit 只用于一次性定位（getCurrentPosition）：无 fix 环境必须秒级
  //   失败，否则启动链路（Init: geohash= 之后的 listening/统计）被整体挂死。
  //   位置流不能带 timeLimit——流被超时杀死后监听静默失效，只能重启恢复。
  static LocationSettings _settings({int distanceFilter = 0, bool timeLimit = true}) =>
      AndroidSettings(
        accuracy: LocationAccuracy.medium,
        distanceFilter: distanceFilter,
        forceLocationManager: true,
        timeLimit: timeLimit ? const Duration(seconds: 8) : null,
      );

  String get currentGeohash => _currentGeohash;
  bool get isRunning => _isRunning;

  /// 取一次定位并换算网格。**可能弹系统授权框**（缺权限时）。
  ///
  /// 2026-11-06 用户定则，勿回退：授权框只允许由「启动时（收听开启）」和「发送声呐」
  /// 这两个入口触发，也就是只有这两处可以调本方法。收听开关是纯标志位，
  /// 开关路径只能用不弹框的 [startLocation]，否则重新开启收听会再次弹授权框。
  Future<String> getGeohash() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          return '';
        }
      }
      if (permission == LocationPermission.deniedForever) {
        return '';
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: _settings(),
      );
      _currentGeohash = encodeGeohash(position.latitude, position.longitude, 6);
      return _currentGeohash;
    } catch (e) {
      DebugLog().write(
        'Location: getGeohash failed: $e; settings=${_settings().toJson()}',
      );
      // Geolocator 不可用的平台（OHOS）走原生定位桥兜底：先补授权，再取定位
      if (!await _nativeEnsurePermission()) return '';
      final fix = await _nativeLocationFix();
      if (fix == null) return '';
      _currentGeohash = encodeGeohash(fix.lat, fix.lon, 6);
      return _currentGeohash;
    }
  }

  /// 启动定位追踪。**永不弹授权框**：没有授权就安静返回（[isRunning] 保持 false）。
  ///
  /// 收听开关开启时走这里（2026-11-06 用户定则，勿改回 requestPermission）。
  Future<void> startLocation(void Function(String geohash)? onChanged) async {
    if (_isRunning) return;

    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }

      _isRunning = true;
      _positionStream = Geolocator.getPositionStream(
        locationSettings: _settings(distanceFilter: 100, timeLimit: false),
      ).listen((position) {
        final geohash = encodeGeohash(position.latitude, position.longitude, 6);
        if (geohash == _currentGeohash) return;
        _currentGeohash = geohash;
        onChanged?.call(_currentGeohash);
      }, onError: (Object e) {
        // 定位流中途报错（权限被收走/服务关闭等）不能静默吞掉
        DebugLog().write('Location: stream error: $e');
      });
    } catch (e) {
      DebugLog().write('Location: startLocation failed: $e');
      // 位置流不可用（OHOS）：降级为单次定位回调（无持续监听）；只查授权不弹框
      _isRunning = false;
      if (!await _nativeHasPermission()) return;
      final fix = await _nativeLocationFix();
      if (fix == null) return;
      final geohash = encodeGeohash(fix.lat, fix.lon, 6);
      if (geohash == _currentGeohash) return;
      _currentGeohash = geohash;
      _isRunning = true;
      onChanged?.call(_currentGeohash);
    }
  }

  void stopLocation() {
    _positionStream?.cancel();
    _positionStream = null;
    _isRunning = false;
  }

  static String encodeGeohash(double lat, double lon, int precision) {
    const base32 = '0123456789bcdefghjkmnpqrstuvwxyz';
    final result = StringBuffer();
    var isLon = true;
    var minLat = -90.0;
    var maxLat = 90.0;
    var minLon = -180.0;
    var maxLon = 180.0;
    var bitCount = 0;
    var value = 0;

    while (result.length < precision) {
      if (isLon) {
        final mid = (minLon + maxLon) / 2;
        if (lon >= mid) {
          value = value * 2 + 1;
          minLon = mid;
        } else {
          value = value * 2;
          maxLon = mid;
        }
      } else {
        final mid = (minLat + maxLat) / 2;
        if (lat >= mid) {
          value = value * 2 + 1;
          minLat = mid;
        } else {
          value = value * 2;
          maxLat = mid;
        }
      }
      isLon = !isLon;
      bitCount++;
      if (bitCount == 5) {
        result.write(base32[value]);
        value = 0;
        bitCount = 0;
      }
    }
    return result.toString();
  }

  @visibleForTesting
  static String encodeGeohashForTesting(double lat, double lon, int precision) {
    return encodeGeohash(lat, lon, precision);
  }
}
