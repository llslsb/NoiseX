import 'dart:async';
import 'package:flutter/material.dart';

/// 对方输入状态管理器
///
/// 职责：
/// - 维护正在输入的房间集合
/// - 4s 超时自动清除
/// - 状态变更通知
class TypingManager extends ChangeNotifier {
  final Set<String> _typingRoomIds = <String>{};
  final Map<String, Timer> _typingTimeouts = <String, Timer>{};

  Set<String> get typingRoomIds => _typingRoomIds;

  /// 检查房间是否有对方正在输入
  bool isTyping(String roomId) => _typingRoomIds.contains(roomId);

  /// 开始输入
  void startTyping(String roomId) {
    _typingTimeouts[roomId]?.cancel();
    _typingRoomIds.add(roomId);
    _typingTimeouts[roomId] = Timer(const Duration(seconds: 4), () {
      stopTyping(roomId);
    });
    notifyListeners();
  }

  /// 停止输入
  void stopTyping(String roomId) {
    _typingTimeouts.remove(roomId)?.cancel();
    if (_typingRoomIds.remove(roomId)) {
      notifyListeners();
    }
  }

  /// 清空所有状态
  void clear() {
    for (final timer in _typingTimeouts.values) {
      timer.cancel();
    }
    _typingTimeouts.clear();
    _typingRoomIds.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    clear();
    super.dispose();
  }
}
