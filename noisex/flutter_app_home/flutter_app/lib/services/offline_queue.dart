import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../models/message.dart';
import 'ws_service.dart';

/// 待发送消息的队列项
class _PendingMessage {
  final String id;
  final String roomId;
  final String content;
  final int retryCount;
  final DateTime createdAt;

  const _PendingMessage({
    required this.id,
    required this.roomId,
    required this.content,
    this.retryCount = 0,
    required this.createdAt,
  });

  _PendingMessage copyWith({
    String? id,
    String? roomId,
    String? content,
    int? retryCount,
    DateTime? createdAt,
  }) {
    return _PendingMessage(
      id: id ?? this.id,
      roomId: roomId ?? this.roomId,
      content: content ?? this.content,
      retryCount: retryCount ?? this.retryCount,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'roomId': roomId,
      'content': content,
      'retryCount': retryCount,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory _PendingMessage.fromJson(Map<String, dynamic> json) {
    return _PendingMessage(
      id: json['id'] as String,
      roomId: json['roomId'] as String,
      content: json['content'] as String,
      retryCount: json['retryCount'] as int? ?? 0,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}

/// 发送结果回调
typedef OfflineMessageCallback = void Function(
  String messageId,
  MessageSendStatus status, {
  String? error,
});

/// 离线消息发送队列服务
///
/// 功能：
/// - 网络断开时缓存消息到本地
/// - 网络恢复后自动补发
/// - 单条消息最多重试 3 次
/// - App 重启后恢复队列
/// - 发送状态实时回调给 UI
class OfflineQueue {
  static final OfflineQueue _instance = OfflineQueue._();
  factory OfflineQueue() => _instance;
  OfflineQueue._();

  static const String _storageKey = 'offline_message_queue';
  static const int _maxRetryCount = 3;
  static const int _maxQueueSize = 50;

  final List<_PendingMessage> _queue = [];
  final List<OfflineMessageCallback> _callbacks = [];
  final StreamController<bool> _offlineStateController =
      StreamController<bool>.broadcast();

  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  bool _isOnline = true;
  bool _isFlushing = false;

  /// 离线状态流：true = 离线，false = 在线
  Stream<bool> get offlineStateStream => _offlineStateController.stream;

  /// 当前是否离线
  bool get isOffline => !_isOnline;

  /// 队列中的消息数量
  int get pendingCount => _queue.length;

  /// 初始化：监听网络状态 + 恢复本地队列
  Future<void> init() async {
    await _loadQueue();
    // 连接监听是平台能力：未装平台适配插件的环境(如 OHOS)下 MissingPluginException
    // 不能阻塞启动，降级为常在线推断，由 WS 连接状态自行纠偏
    try {
      _connectivitySubscription = Connectivity().onConnectivityChanged.listen(
        _handleConnectivityChange,
      );
      // 检查初始网络状态
      final result = await Connectivity().checkConnectivity();
      _isOnline = !result.contains(ConnectivityResult.none);
    } catch (_) {
      _isOnline = true;
    }
    _emitState();
  }

  void dispose() {
    _connectivitySubscription?.cancel();
    _offlineStateController.close();
  }

  /// 添加回调监听
  void addCallback(OfflineMessageCallback callback) {
    _callbacks.add(callback);
  }

  /// 移除回调
  void removeCallback(OfflineMessageCallback callback) {
    _callbacks.remove(callback);
  }

  /// 入队消息（离线时缓存，在线时立即发送）
  Future<String> enqueue(String roomId, String content) async {
    final messageId = _generateId();

    if (_queue.length >= _maxQueueSize) {
      _notifyCallback(messageId, MessageSendStatus.failed,
          error: '队列已满，请稍后重试');
      return messageId;
    }

    final pending = _PendingMessage(
      id: messageId,
      roomId: roomId,
      content: content,
      createdAt: DateTime.now(),
    );

    _queue.add(pending);
    await _saveQueue();

    // 先通知 UI：发送中
    _notifyCallback(messageId, MessageSendStatus.sending);

    // 在线时立即发送
    if (_isOnline && WsService().isConnected) {
      await _trySend(pending);
    }

    return messageId;
  }

  /// 手动触发补发（供 UI 重试按钮使用）
  Future<void> retryAll() async {
    if (_queue.isEmpty) return;
    await _flushQueue();
  }

  /// 清空指定房间的队列（如房间过期/离开时）
  Future<void> clearRoom(String roomId) async {
    _queue.removeWhere((m) => m.roomId == roomId);
    await _saveQueue();
  }

  /// 获取指定房间的待发送消息
  List<String> getPendingForRoom(String roomId) {
    return _queue.where((m) => m.roomId == roomId).map((m) => m.id).toList();
  }

  // ============ 内部实现 ============

  /// 处理网络状态变化
  Future<void> _handleConnectivityChange(
    List<ConnectivityResult> results,
  ) async {
    final wasOffline = !_isOnline;
    _isOnline = !results.contains(ConnectivityResult.none);
    _emitState();

    // 网络从离线 → 在线，且 WebSocket 已连接，触发补发
    if (wasOffline && _isOnline && WsService().isConnected) {
      await _flushQueue();
    }
  }

  /// 批量发送队列中的所有消息
  Future<void> _flushQueue() async {
    if (_isFlushing || _queue.isEmpty) return;

    _isFlushing = true;
    try {
      // 复制一份，避免迭代过程中队列变化
      final toSend = List<_PendingMessage>.from(_queue);
      for (final msg in toSend) {
        if (_queue.contains(msg)) {
          // 可能在发送前用户已手动重试
          await _trySend(msg);
        }
      }
    } finally {
      _isFlushing = false;
    }
  }

  /// 尝试发送单条消息
  Future<void> _trySend(_PendingMessage pending) async {
    if (pending.retryCount >= _maxRetryCount) {
      _queue.remove(pending);
      await _saveQueue();
      _notifyCallback(
        pending.id,
        MessageSendStatus.failed,
        error: '超过最大重试次数',
      );
      return;
    }

    try {
      WsService().sendChat(pending.roomId, pending.content);

      // 发送成功（WebSocket 发送不等待确认，delivered 状态由服务端回执）
      // 这里假设发送成功，真实的 delivered/read 状态由 WsService 驱动
      _queue.remove(pending);
      await _saveQueue();
      _notifyCallback(pending.id, MessageSendStatus.sent);
    } catch (e) {
      // 发送失败，增加重试计数
      final index = _queue.indexOf(pending);
      if (index != -1) {
        _queue[index] = pending.copyWith(retryCount: pending.retryCount + 1);
        await _saveQueue();

        if (_queue[index].retryCount >= _maxRetryCount) {
          _queue.removeAt(index);
          await _saveQueue();
          _notifyCallback(
            pending.id,
            MessageSendStatus.failed,
            error: e.toString(),
          );
        } else {
          // 仍然在队列中，下次网络恢复时重试
          _notifyCallback(pending.id, MessageSendStatus.sending);
        }
      }
    }
  }

  /// 通知所有回调
  void _notifyCallback(
    String messageId,
    MessageSendStatus status, {
    String? error,
  }) {
    for (final callback in _callbacks) {
      callback(messageId, status, error: error);
    }
  }

  /// 持久化队列到 SharedPreferences
  Future<void> _saveQueue() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonList = _queue.map((m) => m.toJson()).toList();
      await prefs.setString(_storageKey, jsonEncode(jsonList));
    } catch (_) {}
  }

  /// 从 SharedPreferences 恢复队列
  Future<void> _loadQueue() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = prefs.getString(_storageKey);
      if (data == null) return;

      final List<dynamic> jsonList = jsonDecode(data) as List<dynamic>;
      _queue.clear();
      for (final item in jsonList) {
        _queue.add(_PendingMessage.fromJson(item as Map<String, dynamic>));
      }
    } catch (_) {}
  }

  /// 发出离线状态事件
  void _emitState() {
    if (!_offlineStateController.isClosed) {
      _offlineStateController.add(!_isOnline);
    }
  }

  /// 生成唯一消息 ID
  String _generateId() {
    return 'local_${DateTime.now().millisecondsSinceEpoch}_${_queue.length}';
  }
}
