import 'package:flutter/material.dart';
import 'services/auth_service.dart';
import 'services/offline_queue.dart';
import 'services/ritual_animation_service.dart';
import 'services/sound_service.dart';
import 'services/storage_service.dart';
import 'app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await StorageService().init();
  await AuthService().init();
  // 初始化短音效服务（资源占位时内部静默失败，不影响 UI）
  await SoundService.instance.init();
  // 初始化离线消息队列（网络状态监听 + 本地缓存恢复）
  await OfflineQueue().init();
  // 清理旧版本遗留的"首次仪式"标志（旧版动效只播一次，现已改为每次都播）
  await RitualAnimationService.instance.cleanupLegacyFirstFlags();

  runApp(const NoiseXApp());
}
