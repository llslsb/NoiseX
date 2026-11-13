import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/constants.dart';
import 'api_service.dart';
import 'auth_service.dart';
import 'debug_log.dart';

typedef WsCallback = void Function(String type, Map<String, dynamic> data);

/// WebSocket 连接状态。供 UI 顶部状态条 [ConnectionStatusBar] 使用。
///
/// 与设计文档 `docs/superpowers/plans/2026-06-15-ux-revamp.md` P0-6 对齐。
enum WsConnectionState { connected, reconnecting, offline }

class WsService {
  static final WsService _instance = WsService._();
  factory WsService() => _instance;
  WsService._();

  WebSocketChannel? _channel;
  Timer? _pingTimer;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  bool _intentionalDisconnect = false;
  bool _isConnecting = false;
  bool _hasConnectedBefore = false;
  // B12：连接建立时刻与心跳计数，用于断连间隔归因
  DateTime? _connectedAt;
  int _pingCount = 0;
  // D-M11-1：服务端最近一帧（含 pong、业务帧）到达时刻，死链判定基线
  DateTime? _lastServerFrameAt;
  // 握手连续失败自愈：token 失效（换服务器/token 轮换/封禁）时 WS 握手永远
  // 被拒而 REST 侧有 401 自动重注册兜底——这里给 WS 补同款逻辑。
  final HandshakeFailureTracker _handshakeTracker = HandshakeFailureTracker();
  bool _connectedThisAttempt = false; // 本次连接是否完成过握手（收到首帧）
  bool _reRegisterPending = false; // 重注册链进行中（onError+onDone 连击去重）

  static const int _maxReconnectDelay = 30;
  static const int _maxReconnectAttempts = 10;
  // D-M11-1：容忍 2 个 ping 周期无回声（服务端健康时 pong 毫秒级返回）
  static const Duration _deadLinkSilence = Duration(seconds: 90);

  final List<WsCallback> _callbacks = [];

  /// 连接状态广播。
  ///
  /// 注意：使用 broadcast 流，可被多个监听者（顶部状态条、调试面板等）共享。
  /// 历史值通过 [currentState] 同步获取，避免新订阅者错过当前态。
  final StreamController<WsConnectionState> _stateController =
      StreamController<WsConnectionState>.broadcast();
  WsConnectionState _currentState = WsConnectionState.offline;

  Stream<WsConnectionState> get connectionStateStream => _stateController.stream;
  WsConnectionState get currentState => _currentState;

  void _emitState(WsConnectionState s) {
    if (_currentState == s) return;
    _currentState = s;
    if (!_stateController.isClosed) {
      _stateController.add(s);
    }
  }

  bool get isConnected => _channel != null;

  void addCallback(WsCallback callback) {
    _callbacks.add(callback);
  }

  void removeCallback(WsCallback callback) {
    _callbacks.remove(callback);
  }

  void connect() {
    if (_isConnecting || _channel != null) return;
    _isConnecting = true;
    _intentionalDisconnect = false;
    _connectedThisAttempt = false;
    // 还在重连中或首次连接前，对外暴露 reconnecting，避免"已连接"的虚假态
    _emitState(_hasConnectedBefore
        ? WsConnectionState.reconnecting
        : WsConnectionState.reconnecting);

    final token = AuthService().jwt;
    if (token == null) {
      DebugLog().write('WS connect aborted: no jwt');
      _isConnecting = false;
      _emitState(WsConnectionState.offline);
      return;
    }

    try {
      _channel = WebSocketChannel.connect(
        Uri.parse('${Constants.wsUrl}?token=$token'),
      );

      _channel!.stream.listen(
        (message) {
          if (!_hasConnectedBefore) {
            _hasConnectedBefore = true;
            _reconnectAttempts = 0;
            DebugLog().write('WS first frame received');
          }
          _connectedThisAttempt = true;
          _handshakeTracker.noteSuccess();
          _connectedAt ??= DateTime.now();
          _lastServerFrameAt = DateTime.now();
          // 收到第一帧表明连接已建立
          _emitState(WsConnectionState.connected);
          _handleMessage(message);
        },
        onError: (error) {
          DebugLog().write('WS stream error: $error');
          _handleDisconnect();
        },
        onDone: () {
          DebugLog().write('WS stream done (closed code 1006 = abnormal)');
          _handleDisconnect();
        },
      );

      _startPing();
      _isConnecting = false;
      // 连接成功（建立通道后立即标记 connected；首帧到达再次确认）
      _emitState(WsConnectionState.connected);

      if (_hasConnectedBefore) {
        _notifyCallbacks('reconnected', {});
      }
    } catch (e) {
      DebugLog().write('WS connect threw: $e');
      _isConnecting = false;
      _scheduleReconnect();
    }
  }

  void disconnect() {
    _intentionalDisconnect = true;
    _pingTimer?.cancel();
    _reconnectTimer?.cancel();
    _channel?.sink.close();
    _channel = null;
    _reconnectAttempts = 0;
    _emitState(WsConnectionState.offline);
  }

  void reconnect() {
    disconnect();
    Timer(const Duration(seconds: 1), () => connect());
  }

  void sendChat(String roomId, String content) {
    _send({'type': 'chat', 'roomId': roomId, 'content': content});
  }

  void sendDeepConfirm(String roomId) {
    _send({'type': 'deep_confirm', 'roomId': roomId});
  }

  void sendRead(String roomId, String messageId) {
    _send({'type': 'read', 'roomId': roomId, 'messageId': messageId});
  }

  void sendKeyExchange(String roomId, String pubKey) {
    _send({'type': 'key_exchange', 'roomId': roomId, 'pubKey': pubKey});
  }

  /// 发送 typing 信令（不持久化；客户端 4s 兜底自行清除）。
  ///
  /// 与计划文档 docs/superpowers/plans/2026-06-15-ux-revamp.md P1-C 对齐。
  void sendTyping(String roomId, {required bool isStart}) {
    _send({
      'type': isStart ? 'typing_start' : 'typing_stop',
      'roomId': roomId,
    });
  }

  void _send(Map<String, dynamic> data) {
    final channel = _channel;
    if (channel == null) {
      // B13：断连窗口内的发送不再无声丢弃——落盘留证并触发快速重连，
      // 让下一条消息有机会在连接恢复后发出。
      DebugLog().write('WS send dropped (channel==null): ${data['type']}');
      connect();
      return;
    }
    try {
      channel.sink.add(jsonEncode(data));
    } catch (e) {
      // sink 已关闭/底层 socket 异常：立即走断连重连，避免继续黑洞发送
      DebugLog().write('WS send error (${data['type']}): $e');
      _handleDisconnect();
    }
  }

  void _notifyCallbacks(String type, Map<String, dynamic> data) {
    for (final callback in _callbacks) {
      callback(type, data);
    }
  }

  void _handleMessage(dynamic raw) {
    try {
      final data = jsonDecode(raw as String) as Map<String, dynamic>;
      final type = data['type'] as String? ?? '';
      if (type != 'pong') {
        DebugLog().write('WS recv: $type');
      }
      for (final callback in _callbacks) {
        callback(type, data);
      }
    } catch (e) {
      DebugLog().write('WS message parse error: $e');
    }
  }

  void _handleDisconnect() {
    final connectedAt = _connectedAt;
    if (connectedAt != null) {
      final uptime = DateTime.now().difference(connectedAt);
      DebugLog().write('WS disconnected after ${uptime.inSeconds}s');
      _connectedAt = null;
    }
    _pingTimer?.cancel();
    _channel = null;
    _notifyCallbacks('connectionChanged', {'connected': false});
    if (_intentionalDisconnect) {
      _emitState(WsConnectionState.offline);
      return;
    }

    // 本次从未收到首帧就断了 = 握手被拒（多为 token 失效）。连续 N 次 →
    // 幂等重注册拿新 token（本地 uuid 不变，身份/房间/监听不受影响），
    // 注册完成后再排下一次连接，避免旧 token 继续白连。
    if (!_connectedThisAttempt) {
      final shouldReRegister =
          _handshakeTracker.noteFailure(DateTime.now());
      if (shouldReRegister) {
        if (_reRegisterPending) return; // onError/onDone 连击去重
        _reRegisterPending = true;
        DebugLog().write(
            'WS handshake failed x${_handshakeTracker.streak}, force re-register');
        () async {
          await _reRegisterForNewToken();
          _reRegisterPending = false;
          if (!_intentionalDisconnect) {
            _emitState(WsConnectionState.reconnecting);
            _scheduleReconnect();
          }
        }();
        return;
      }
    } else {
      _handshakeTracker.noteSuccess();
    }

    _emitState(WsConnectionState.reconnecting);
    _scheduleReconnect();
  }

  /// 用本地 anonymousUuid 幂等重注册：服务器按 uuid 返回同一用户新 token。
  /// 旧 token 失效（换服务器/过期/轮换）时的唯一自愈路径——refresh 接口
  /// 带 Bearer 旧 token，同样会被拒，救不了这种场景。
  Future<void> _reRegisterForNewToken() async {
    _handshakeTracker.noteReRegister(DateTime.now());
    final userId = AuthService().userId;
    if (userId == null || userId.isEmpty) {
      DebugLog().write('WS re-register skipped: no local uuid');
      return;
    }
    try {
      final result = await ApiService().register(userId);
      if (result.isSuccess && result.data != null) {
        await AuthService().saveAuth(result.data!.token, userId);
        DebugLog().write('WS re-register ok: new token saved (uuid unchanged)');
      } else {
        DebugLog().write('WS re-register failed: ${result.message}');
      }
    } catch (e) {
      DebugLog().write('WS re-register threw: $e');
    }
  }

  void _startPing() {
    _pingTimer?.cancel();
    _pingCount = 0;
    // 基线取连接时刻：首个周期内不该因"从未收到帧"误判
    _lastServerFrameAt = DateTime.now();
    _pingTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _pingCount++;
      // B12：每 2 分钟记录一次存活心跳，用于断连间隔归因
      if (_pingCount % 4 == 0) {
        DebugLog().write('WS ping #$_pingCount (alive)');
      }
      _send({'type': 'ping'});
      // D-M11-1 死链自愈：TCP 半开时 sink.add 只进本地缓冲不报错，
      // onError/onDone 永不触发（M11 实测：断网后红条要等下次业务发送
      // 才出现）。连续 3 个周期（90s）收不到服务端任何帧（含 pong）即判
      // 死链：主动断开走标准断连路径，红条立刻出现，恢复后自动补齐。
      if (isDeadLinkSilence(
          lastServerFrameAt: _lastServerFrameAt, now: DateTime.now())) {
        DebugLog().write(
            'WS dead link detected: no server frame for '
            '${_deadLinkSilence.inSeconds}s+, force reconnect');
        _teardownDeadLink();
      }
    });
  }

  /// D-M11-1 死链判定：自基线时刻起连续 [=_deadLinkSilence] 无服务端帧。
  /// 纯函数便于单测；null 基线（从未连接）不判死。
  @visibleForTesting
  static bool isDeadLinkSilence(
      {required DateTime? lastServerFrameAt, required DateTime now}) {
    return lastServerFrameAt != null &&
        now.difference(lastServerFrameAt) >= _deadLinkSilence;
  }

  /// 死链主动拆除：不等 onError/onDone（半开链路上它们不会来），直接
  /// 走 _handleDisconnect 标准路径（红条 + 指数退避重连）；sink 尽力关闭。
  void _teardownDeadLink() {
    _pingTimer?.cancel();
    try {
      _channel?.sink.close();
    } catch (e) {
      DebugLog().write('WS dead link close threw: $e');
    }
    _channel = null;
    _handleDisconnect();
  }

  void _scheduleReconnect() {
    if (_reconnectTimer != null) return;
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      DebugLog().write('WS reconnect gave up: attempts=$_reconnectAttempts');
      _emitState(WsConnectionState.offline);
      return;
    }

    final delay = math.min(_maxReconnectDelay, math.pow(2, _reconnectAttempts).toInt());
    DebugLog().write(
        'WS reconnect scheduled: attempt=$_reconnectAttempts delay=${delay}s');
    _reconnectAttempts++;
    _reconnectTimer = Timer(Duration(seconds: delay), () {
      _reconnectTimer = null;
      connect();
    });
  }
}

/// 握手连续失败追踪：连续 [threshold] 次"未握手即断"且过了 [cooldown]
/// 冷却期 → 建议触发重注册。纯状态机、无 IO，时间由调用方注入以便单测。
class HandshakeFailureTracker {
  HandshakeFailureTracker({
    this.threshold = 3,
    this.cooldown = const Duration(minutes: 2),
  });

  final int threshold;
  final Duration cooldown;
  int streak = 0;
  DateTime? lastReRegisterAt;

  /// 记录一次握手失败，返回是否达到"应重注册"条件。
  bool noteFailure(DateTime now) {
    streak++;
    final cooldownOk =
        lastReRegisterAt == null || now.difference(lastReRegisterAt!) > cooldown;
    return streak >= threshold && cooldownOk;
  }

  /// 收到首帧（握手成功）→ 计数归零。
  void noteSuccess() => streak = 0;

  /// 重注册已执行：计数归零并盖冷却时间戳。
  void noteReRegister(DateTime now) {
    streak = 0;
    lastReRegisterAt = now;
  }
}
