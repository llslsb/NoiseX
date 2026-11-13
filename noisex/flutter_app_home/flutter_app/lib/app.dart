import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'theme/colors.dart';
import 'theme/animations.dart';
import 'theme/page_transitions.dart';
import 'theme/scroll_physics.dart';
import 'models/sonar.dart';
import 'models/chat_room.dart';
import 'models/message.dart';
import 'models/constants.dart';
import 'models/api_types.dart';
import 'services/auth_service.dart';
import 'services/api_service.dart';
import 'services/debug_log.dart';
import 'services/haptic_service.dart';
import 'services/sound_service.dart';
import 'services/ws_service.dart';
import 'services/location_service.dart';
import 'services/crypto_service.dart';
import 'services/push_service.dart';
import 'services/storage_service.dart';
import 'services/status_bar_service.dart';
import 'utils/listening_registration_utils.dart';
import 'utils/room_sync_utils.dart';
import 'utils/error_messages.dart';
import 'state/room_manager.dart';
import 'state/typing_manager.dart';
import 'state/ws_event_handler.dart';
import 'state/sonar_manager.dart';
import 'state/room_operations.dart';
import 'pages/splash_page.dart';
import 'pages/privacy_agreement_page.dart';
import 'pages/onboarding_page.dart';
import 'pages/sonar_page.dart';
import 'pages/receiver_page.dart';
import 'pages/hourglass_page.dart';
import 'pages/chat_page.dart';
import 'pages/profile_page.dart';
import 'pages/report_page.dart';
import 'widgets/connection_status_bar.dart';
import 'widgets/tab_bar.dart';

class NoiseXApp extends StatelessWidget {
  const NoiseXApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NoiseX',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: AppColors.bgBase,
        colorScheme: const ColorScheme.dark(
          primary: AppColors.primary,
          surface: AppColors.bgBase,
          error: AppColors.error,
        ),
        fontFamily: 'JetBrains Mono',
        useMaterial3: true,
      ),
      home: const UnifiedScrollConfiguration(
        child: MainPage(),
      ),
    );
  }
}

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  /// 自建系统通道（OHOS EntryAbility.ets 注册，单源勿单边改）：
  /// moveToBackground = 应用退到后台（对齐鸿蒙端首页返回键默认行为）
  static const MethodChannel _systemChannel = MethodChannel('noisex/system');

  bool _showSplash = true;
  bool _showPrivacyGate = false;
  bool _showOnboarding = false;
  String _activeTab = 'sonar';
  bool _showProfile = false;
  double _statusBarHeight = 0;

  // 柔光模式（22:00-06:00 自动启用，减少蓝光）
  bool _softLightEnabled = true;
  bool _softLightAuto = true;
  String _listeningGeohash = '';

  /// 附近活跃用户数与雷达 blip 数（P2-B 雷达 blip 真实化）。
  /// [_nearbyCount] 为 0 表示尚未加载，UI 显示"正在探测附近信号..."。
  int _nearbyCount = 0;
  bool _nearbyLoaded = false;
  int _blipCount = 0;
  Timer? _nearbyActivityTimer;
  final ListeningOperationGate _listeningOperationGate =
      ListeningOperationGate();

  // 模块化状态管理
  late final RoomManager _roomManager;
  late final TypingManager _typingManager;
  late final WsEventHandler _wsEventHandler;
  late final SonarManager _sonarManager;
  late final RoomOperations _roomOperations;

  /// 房间列表（从 _roomManager 获取，提供给 Widget 使用）
  List<ChatRoom> get _rooms => _roomManager.rooms;

  /// 当前房间（从 _roomManager 获取，提供给 Widget 使用）
  ChatRoom? get _currentRoom => _roomManager.currentRoom;

  /// 收到的声呐列表（从 _sonarManager 获取）
  List<Sonar> get _receivedSonars => _sonarManager.receivedSonars;

  /// 是否正在收听（从 _sonarManager 获取）
  bool get _isListening => _sonarManager.isListening;

  /// 声呐冷却剩余秒数（从 _sonarManager 获取）
  int get _sonarCooldown => _sonarManager.sonarCooldown;

  /// typing 状态（从 _typingManager 获取，提供给 Widget 使用）
  bool isPeerTyping(String roomId) => _typingManager.isTyping(roomId);

  @override
  void initState() {
    super.initState();
    _initStateManagers();
    _setupPushNavigation();
    _watchWsReconnect();
  }

  /// B15：WS 重连成功后同步服务端数据（对齐鸿蒙端 onReconnected → 同步数据）。
  ///
  /// connectionStateStream 只在状态变化时发事件：offline/reconnecting → connected
  /// 即代表一次真实的重连恢复；首次启动的 connected 由 _initState 里显式刷新覆盖。
  void _watchWsReconnect() {
    WsConnectionState previous = WsService().currentState;
    WsService().connectionStateStream.listen((state) {
      final wasDisconnected = previous != WsConnectionState.connected;
      previous = state;
      if (state == WsConnectionState.connected && wasDisconnected) {
        DebugLog().write('WS reconnected: syncing lists');
        _sonarManager.refreshReceivedSonars();
        _refreshRooms();
        // 断连窗口内错过的消息不靠房间列表接口带回，补一轮消息流同步
        unawaited(_syncRoomMessagesForBadges());
        unawaited(_reRegisterListeningAfterReconnect());
      }
    });
  }

  /// 重连即补登收听（2026-11-06 用户定，勿删）。
  ///
  /// 「附近 N 人」只计 WS 在线且在收听名单里的人（服务端 MatchEngine.countNearbyListeners）。
  /// 掉线期间服务端会把本机移出名单，本地 _listeningGeohash 却仍以为在册——不 force 就会被
  /// shouldUpdateListeningRegistration 的同格去重跳过，要等下一个 App 事件才补回，空档期
  /// 对方看你是「附近 0 人」（2026-11-06 双机实锤：鸿蒙看安卓 1 人、安卓看鸿蒙 0 人）。
  /// 从未登记成功时用定位服务已知的网格补登；一个都没有就跳过，等定位回调登记——
  /// 这里不能调 getGeohash，否则网络一抖重连就可能冒出授权框（2026-11-06 用户定则）。
  ///
  /// 静默模式下绝不补登；若关闭收听时注销请求失败、本地仍残留登记格，借重连再补发一次注销
  /// （注销幂等），保证「静默=服务端不在收听名单」最终一致。
  Future<void> _reRegisterListeningAfterReconnect() async {
    if (!AuthService().isAuthenticated) return;
    if (!_isListening) {
      if (_listeningGeohash.isNotEmpty) {
        DebugLog().write('WS reconnected: retry unregister (silent mode)');
        await _stopListeningRegistration();
      }
      return;
    }
    final geohash = _listeningGeohash.isNotEmpty
        ? _listeningGeohash
        : LocationService().currentGeohash;
    if (geohash.isEmpty) return;
    DebugLog().write('WS reconnected: re-register listening');
    await _startListeningAt(geohash, force: true);
  }

  /// B15：切到接收器/沙漏 Tab 时拉取最新列表。
  ///
  /// 对齐鸿蒙端 Tabs 切换语义：TabContent 可见即持有最新数据；
  /// 1.5s 节流避免快速来回切换时打爆接口。
  DateTime _lastTabRefresh = DateTime.fromMillisecondsSinceEpoch(0);

  Future<void> _refreshOnTabSwitch(String tab) async {
    final now = DateTime.now();
    if (now.difference(_lastTabRefresh) < const Duration(milliseconds: 1500)) {
      return;
    }
    _lastTabRefresh = now;
    if (tab == 'receiver') {
      await _sonarManager.refreshReceivedSonars();
    } else if (tab == 'hourglass') {
      await _refreshRooms();
      unawaited(_syncRoomMessagesForBadges());
    }
  }

  /// 正在后台同步消息流的房间集合：防下拉刷新/切 Tab/重连三路并发重复拉取
  final Set<String> _roomMessageSyncInFlight = <String>{};

  /// 后台逐房间同步消息流：让沙漏未读角标（tab 徽标 + 卡片 💬 徽标）与
  /// 最后消息预览在重启/重连后立即可用。
  ///
  /// 2026-11-03 Mate X7 实锤：重启后房间从服务端列表重建时 messages 为空，
  /// unreadCount（基于消息流计算）恒 0，徽标要等点进房间触发权威校准才
  /// 出现——接收器角标快（声呐列表自带状态）、沙漏角标慢的差速即由此来。
  /// 复用 [_reloadRoomFromServer]（服务端权威流+解密+缓存自愈，与进房
  /// 同款路径），顺序逐房间执行避免打爆接口；跳过正在打开的房间
  ///（聊天页自己会校准）。
  Future<void> _syncRoomMessagesForBadges() async {
    for (final room in List<ChatRoom>.from(_rooms)) {
      if (!mounted) return;
      if (_roomMessageSyncInFlight.contains(room.id)) continue;
      if (_currentRoom?.id == room.id) continue;
      _roomMessageSyncInFlight.add(room.id);
      try {
        await _reloadRoomFromServer(room.id);
      } finally {
        _roomMessageSyncInFlight.remove(room.id);
      }
    }
  }

  /// 初始化状态管理模块
  void _initStateManagers() {
    _roomManager = RoomManager();
    _typingManager = TypingManager();
    _sonarManager = SonarManager();
    _roomOperations = RoomOperations(_roomManager);
    _wsEventHandler = WsEventHandler(_roomManager, _typingManager,
        sonarManager: _sonarManager);

    // 监听状态变化以触发 UI 重建
    _roomManager.addListener(_onStateChanged);
    _typingManager.addListener(_onStateChanged);
    _sonarManager.addListener(_onStateChanged);
    _roomOperations.addListener(_onStateChanged);
    _wsEventHandler.addListener(_onStateChanged);

    // 注册 WS 回调
    _wsEventHandler.registerCallbacks();
  }

  void _onStateChanged() {
    setState(() {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final topPadding = MediaQuery.of(context).padding.top;
    if (topPadding != _statusBarHeight) {
      _statusBarHeight = topPadding;
      StatusBarService().update(topPadding);
    }
    // 将 BuildContext 附加给需要显示 UI 的管理器
    _wsEventHandler.attach(context);
  }


  void _setupPushNavigation() {
    PushService().onNotificationClick = (roomId) {
      final room = _roomManager.findRoom(roomId);
      if (room != null) {
        _handleEnterRoom(roomId);
      }
    };
  }

  // 使用 _roomManager.upsertRoom 替代内联实现，_mergeRoom 逻辑已迁移到 RoomManager

  // E2EE 密钥交换方法保留在 MainPage 中（RoomManager 不处理加密逻辑）
  Future<void> _ensureRoomKeyExchange(String roomId) async {
    if (CryptoService().hasSharedKey(roomId) ||
        CryptoService().hasKeyPair(roomId)) return;
    final pubKey = await CryptoService().generateKeyPair(roomId);
    if (pubKey.isNotEmpty) {
      WsService().sendKeyExchange(roomId, pubKey);
    }
  }

  Future<void> _syncServerTime() async {
    try {
      final result = await ApiService().getServerTime();
      if (result.isSuccess &&
          result.data != null &&
          result.data!.serverTime > 0) {
        updateServerTimeOffset(result.data!.serverTime);
      }
    } catch (e) {
      debugPrint('[NoiseX] Sync server time failed: $e');
    }
  }

  Future<void> _startLocationTracking() async {
    await LocationService().startLocation((geohash) {
      if (!_isListening || !AuthService().isAuthenticated) return;
      _startListeningAt(geohash);
    });
  }

  /// 启动附近活跃用户数周期轮询（每 30s）。
  /// geohash 生效、变化或 WS 重连时调用以重置周期。
  void _startNearbyActivityPolling() {
    _nearbyActivityTimer?.cancel();
    _nearbyActivityTimer = Timer.periodic(
        const Duration(seconds: 30), (_) => _refreshNearbyActivity());
    unawaited(_refreshNearbyActivity());
  }

  Future<void> _refreshNearbyActivity() async {
    final geohash = _listeningGeohash;
    if (geohash.isEmpty || !AuthService().isAuthenticated) return;
    try {
      final result = await ApiService().getNearbyActivity(geohash);
      if (result.isSuccess && result.data != null && mounted) {
        setState(() {
          _nearbyCount = result.data!.nearbyCount;
          _blipCount = result.data!.blipCount;
          _nearbyLoaded = true;
        });
      }
    } catch (e) {
      debugPrint('[NoiseX] Refresh nearby activity failed: $e');
    }
  }

  Future<bool> _startListeningAt(String geohash, {bool force = false}) async {
    if (!shouldUpdateListeningRegistration(
      registeredGeohash: _listeningGeohash,
      nextGeohash: geohash,
      force: force,
    )) {
      return true;
    }

    final operationId = _listeningOperationGate.next();
    final previousGeohash = _listeningGeohash;

    if (previousGeohash.isNotEmpty && previousGeohash != geohash) {
      try {
        final result = await ApiService().stopListening(previousGeohash);
        if (!result.isSuccess) {
          debugPrint(
              '[NoiseX] Stop previous listening failed: ${result.message}');
          return false;
        }
      } catch (e) {
        debugPrint('[NoiseX] Stop previous listening failed: $e');
        return false;
      }
    }

    if (!_listeningOperationGate.isCurrent(operationId)) return false;

    try {
      final result = await ApiService().startListening(geohash);
      if (!_listeningOperationGate.isCurrent(operationId)) return false;
      if (result.isSuccess) {
        _listeningGeohash = geohash;
        // 测试期观测：注册成功的格值（上架前移除）
        DebugLog().write('Listen: registered geohash=$geohash');
        // geohash 生效后启动附近活跃用户数轮询（雷达 blip 真实化）
        _startNearbyActivityPolling();
        return true;
      }
      DebugLog().write('Listen: start failed: ${result.message}');
      debugPrint('[NoiseX] Start listening failed: ${result.message}');
      return false;
    } catch (e) {
      debugPrint('[NoiseX] Start listening failed: $e');
      return false;
    }
  }

  Future<bool> _stopListeningRegistration() async {
    final previousGeohash = _listeningGeohash;
    _listeningOperationGate.next();
    if (previousGeohash.isEmpty) return true;

    try {
      final result = await ApiService().stopListening(previousGeohash);
      if (result.isSuccess) {
        _listeningGeohash = '';
        return true;
      }
      debugPrint('[NoiseX] Stop listening failed: ${result.message}');
      return false;
    } catch (e) {
      debugPrint('[NoiseX] Stop listening failed: $e');
      return false;
    }
  }

  /// 华为审核要求：首启须先征得《用户协议》与《隐私政策》同意，
  /// 同意前不得注册鉴权、不得连接网络、不得申请任何权限
  ///（[StorageService] 已在 main() 完成初始化，此处可同步读标记）。
  /// 协议版本化键：政策重大变更时改 vN 可对老用户重新弹出。
  void _checkPrivacyGate() {
    final agreed = StorageService().getBool(Constants.prefsKeyPrivacyAgreed);
    if (!agreed) {
      setState(() => _showPrivacyGate = true);
    } else {
      _checkOnboarding();
    }
  }

  void _checkOnboarding() {
    // 检查是否已完成 onboarding
    final completed = StorageService().getBool('onboarding_completed');
    if (!completed) {
      setState(() => _showOnboarding = true);
    } else {
      _initAfterSplash();
    }
  }

  /// 不同意协议：二次确认后退出应用（审核要求"不同意不给使用"）。
  void _confirmExitOnDisagree() {
    HapticService.instance.light();
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        title: const Text(
          '温馨提示',
          style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary),
        ),
        content: const Text(
          '不同意《用户协议》与《隐私政策》将无法使用 NoiseX，'
          '确定要退出应用吗？',
          style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('再看看',
                style: TextStyle(color: AppColors.primary)),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              _exitApp();
            },
            child: const Text('退出应用',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
        ],
      ),
    );
  }

  /// 退出应用：OHOS 走原生通道 terminateSelf（fork 的 SystemNavigator.pop
  /// 落 router.back()，Ability UI 状态被破坏、热重启黑屏，实测 2026-11-01）；
  /// 其余平台回落 SystemNavigator.pop（Android 结束 Activity）。
  Future<void> _exitApp() async {
    try {
      final handled = await _systemChannel.invokeMethod<bool>('exitApp');
      if (handled == true) return;
    } on MissingPluginException {
      // 非 OHOS 平台无此通道实现
    } catch (e) {
      debugPrint('[NoiseX] exitApp failed: $e');
    }
    await SystemNavigator.pop();
  }

  Future<void> _initAfterSplash() async {
    // 初始化本地存储
    await StorageService().init();
    // B18：恢复持久化的 E2EE 共享密钥（重启后历史可解密、加密会话可续）
    await CryptoService().restorePersistedKeys();

    final auth = AuthService();
    try {
      if (!auth.isAuthenticated) {
        final uuid = auth.generateUUID();
        final result = await ApiService().register(uuid);
        if (result.isSuccess && result.data != null) {
          await auth.saveAuth(result.data!.token, uuid);
        }
      } else {
        try {
          final result = await ApiService().refreshToken();
          if (result.isSuccess && result.data != null) {
            await auth.saveAuth(result.data!.token, auth.userId ?? '');
          }
        } catch (e) {
          debugPrint('[NoiseX] Token refresh failed, re-registering: $e');
          final uuid = auth.generateUUID();
          final result = await ApiService().register(uuid);
          if (result.isSuccess && result.data != null) {
            await auth.saveAuth(result.data!.token, uuid);
          }
        }
      }
    } catch (e) {
      debugPrint('[NoiseX] Init auth failed: $e');
    }

    await _syncServerTime();
    DebugLog().write('Init: server time ok');

    WsService().connect();
    // 推送初始化紧跟认证完成（token 上报需要 Authorization）：
    // ❗不能放在函数末尾——中间任何一步（房间/声呐刷新、定位）挂起都会
    // 让"每次启动调 getToken"落空（2026-11-05 安卓模拟器实锤：WS 首帧
    // 后链路停滞 2 分钟+，push init 始终未到达）
    try {
      await PushService().init();
    } catch (e) {
      debugPrint('[NoiseX] Push init failed: $e');
    }

    await _sonarManager.refreshReceivedSonars();
    DebugLog().write('Init: sonars refreshed');
    await _refreshRooms();
    DebugLog().write('Init: rooms refreshed');
    // 重启后房间消息流为空（未读角标/最后消息预览都算不出来），后台逐房间
    // 补同步；不 await，不阻塞首页出现
    unawaited(_syncRoomMessagesForBadges());

    // 静默模式（用户关掉收听且已持久化）启动时不取定位、不登记收听、不开定位追踪——
    // 与隐私政策「位置仅在发送声呐时以及开启收听期间获取」一致（2026-11-06，勿删此分支）
    if (!_isListening) {
      DebugLog().write('Init: silent mode, skip location & listening');
      return;
    }
    final geohash = await LocationService().getGeohash();
    // 测试期观测：打印格值定位匹配问题（geohash-6≈1km 格，非敏感粒度；上架前移除）
    DebugLog().write('Init: geohash=${geohash.isEmpty ? 'empty' : geohash}');
    if (geohash.isNotEmpty) {
      await _startListeningAt(geohash);
    }
    DebugLog().write('Init: listening started');
    await _startLocationTracking();
    DebugLog().write('Init: location tracking ok');
  }

  Future<void> _handleSonarSent(String content) async {
    await _sonarManager.sendSonar(context, content);
  }

  // _startSonarCooldown 已移至 SonarManager 内部管理

  Future<void> _handleAcceptSonar(Sonar sonar) async {
    final room = await _sonarManager.acceptSonar(context, sonar);
    if (room != null) {
      _roomManager.upsertRoom(room);
      setState(() {
        _activeTab = 'hourglass';
      });
      await _ensureRoomKeyExchange(room.id);
    }
  }

  Future<void> _handleIgnoreSonar(String sonarId) async {
    await _sonarManager.ignoreSonar(context, sonarId);
  }

  Future<void> _handleEnterRoom(String roomId) async {
    final room = _roomManager.findRoom(roomId);
    if (room == null) return;

    // 对齐鸿蒙端 ChatPage aboutToAppear：进入时后台重载房间详情+消息流。
    // 内存里的列表可能带着上次会话的残留（WS 追加缺口/缓存脏行），
    // 以服务端权威流校准，未读基准与气泡已读指针一并恢复。
    unawaited(_reloadRoomFromServer(roomId));

    // 先显示加载中的房间（乐观显示，提升响应速度）
    await _roomOperations.enterRoom(context, roomId);

    // 使用 Navigator.push 推入聊天页，支持 Cupertino 右滑返回
    if (!mounted) return;
    await Navigator.of(context).push(
      SlideRightPageRoute(
        builder: (context) => ChatPage(
          room: room,
          // B15 收尾：聊天页监听房间状态源，收发消息实时反映到当前页面
          roomListenable: _roomManager,
          onLeave: _handleLeaveRoom,
          onUnlock: _handleUnlock,
          onSave: _handleSave,
          onReport: (roomId) {
            // 举报页以路由推入（对齐鸿蒙端 navPathStack.pushPath）：
            // 返回键回到聊天页。此前用根级 setState 切 home，被压在聊天
            // 路由之下永远不可见（真机实锤的缺陷）。
            // UI 评审 P0：界面只显示匿名信号码，内部 roomId 不再上屏。
            if (!mounted) return;
            final room = _roomManager.findRoom(roomId);
            Navigator.of(context).push(
              SlideRightPageRoute(
                builder: (context) => ReportPage(
                  roomId: roomId,
                  signalCode: room?.signalCode ?? '',
                  onBack: () => Navigator.of(context).pop(),
                ),
              ),
            );
          },
          onConfirmDeep: _handleConfirmDeep,
          onMarkRead: (roomId, msgId) => WsService().sendRead(roomId, msgId),
          onBlock: _handleBlock,
          onSendMessage: _handleSendMessage,
          onSaveMoment: _handleSaveMoment,
          statusBarHeight: _statusBarHeight,
          peerIsTyping: isPeerTyping(room.id),
          // typing 指示器的实时驱动：peerIsTyping 只是进房快照，路由不随
          // 父级 setState 重建，进房后到来的 typing 事件靠 TypingManager
          // 的 Listenable 通知（2026-11-05 双端实测静态快照永不更新）。
          typingManager: _typingManager,
        ),
      ),
    );

    // 页面弹出后清理当前房间状态
    _roomManager.setCurrentRoom(null);
    PushService().setCurrentRoom(null);

    // 后台加载最新房间数据和消息
    await _reloadRoomFromServer(roomId);
  }

  /// 从服务端重载房间详情 + 消息流（进聊天页与退聊天页共用）。
  ///
  /// 2026-11-02 重构：原实现只在"退出聊天页"后重载一次，且 REST 失败时
  /// 用本地 SQLite 缓存【整表替换】内存消息——缓存里混着旧 bug 时代的
  /// 脏行（own 消息存成 other、'msg-' 本地 id 与服务端流 id 双份），替换后
  /// 未读徽标被顶成幻影值、气泡全部变"对方"，随每次进出在 0↔2 间闪烁
  /// （TestPhone 插桩日志实锤 21 行脏缓存整表覆盖 11 行服务端流）。
  /// 现在：
  /// - 成功路径：服务端流为权威，按 id 去重合并（防 WS 与 REST 竞态丢帧），
  ///   并回写本地缓存自愈脏行；
  /// - 失败路径：只做"补漏"合并，绝不用缓存整表替换内存；
  /// - 两个路径都恢复对方已读指针（气泡 ✓✓）与我方未读基准。
  Future<void> _reloadRoomFromServer(String roomId) async {
    if (!mounted) return;
    final roomResult = await ApiService().getRoom(roomId);
    if (roomResult.isSuccess && roomResult.data != null && mounted) {
      final roomData = roomResult.data!;
      final existing = _roomManager.findRoom(roomId);
      if (existing != null) {
        _roomManager.upsertRoom(
          existing.copyWith(
            sonarContent: roomData.sonarContent,
            signalCode: roomData.signalCode,
            expiresAt: DateTime.fromMillisecondsSinceEpoch(roomData.expiresAt),
            createdAt: roomData.createdAt > 0
                ? DateTime.fromMillisecondsSinceEpoch(roomData.createdAt)
                : existing.createdAt,
            unlocked: roomData.unlocked,
            deepConnectionAchieved: roomData.deepConnectionAchieved,
            deepConnectionConfirmed: roomData.deepConnectionConfirmed,
            bothDeepConfirmed: roomData.bothDeepConfirmed,
            lastReadMessageId: roomData.lastReadMessageId,
          ).applyServerSaveState(
            savedConnection: roomData.savedConnection,
            mySaveConfirmed: roomData.mySaveConfirmed,
            bothSaveConfirmed: roomData.bothSaveConfirmed,
          ),
          moveToTop: false,
        );
        _roomManager.applyPeerReadPointer(roomId, roomData.peerReadMessageId);
      }
    }

    try {
      final result = await ApiService().getMessages(roomId);
      if (result.isSuccess && result.data != null) {
        var messages = result.data!.messages
            .map((m) => Message(
                  id: m.id,
                  roomId: roomId,
                  // 后端 getMessages 已按请求方把 sender 归一化成 "me"/"other"
                  // （ChatService.java: sender.equals(userId) ? "me" : "other"），
                  // 直接透传；旧版拿它跟 UUID 比较恒为 false，每次重载把
                  // 自己的消息全部翻成"对方"（对号/气泡位置全错）
                  sender: m.sender == 'me' ? 'me' : 'other',
                  content: m.content,
                  timestamp: DateTime.fromMillisecondsSinceEpoch(m.timestamp),
                ))
            .toList();

        if (CryptoService().hasSharedKey(roomId)) {
          // 服务端两个方向的消息存的都是密文，必须全量解密。旧版只解
          // other——自己发的消息重载后渲染成密文（2026-11-03 实锤截图）。
          // 本函数与 room_operations._loadRoomMessages 并发跑（进聊天页），
          // 两侧口径一致后，谁后落地结果都相同，不再有密文/明文翻转竞态。
          messages = await Future.wait(messages.map((m) async {
            final decrypted = await CryptoService().decrypt(roomId, m.content);
            return m.copyWith(content: decrypted ?? m.content);
          }));
        }

        final existing = _roomManager.findRoom(roomId);
        if (existing != null && mounted) {
          final merged = _mergeServerMessages(existing.messages, messages);
          _roomManager.upsertRoom(
            existing.copyWith(messages: merged),
            moveToTop: false,
          );
          // 消息行是全新构造（isRead=false），已读指针必须在合并后补应用，
          // 否则重启/重进后自己的消息永远单勾 ✓（boot 时 applyPeerReadPointer
          // 跑在消息加载之前，标记落在了空列表上）
          _roomManager.applyPeerReadPointer(roomId, existing.peerReadMessageId);
          // 缓存自愈：用服务端权威流整体回写 SQLite，洗掉历史脏行
          // （旧 bug 时代 own 消息存成 other / 'msg-' 与流 id 双份）。
          unawaited(StorageService().replaceRoomMessages(
            roomId,
            messages
                .map((m) => <String, dynamic>{
                      'id': m.id,
                      'sender': m.sender,
                      'content': m.content,
                      'timestamp': m.timestamp.millisecondsSinceEpoch,
                    })
                .toList(),
          ));
        }
      }
    } catch (e) {
      debugPrint('[NoiseX] Load messages failed, merging cache extras: $e');
      final room = _roomManager.findRoom(roomId);
      if (room == null || !mounted) return;
      final localMessages = await StorageService().getMessages(roomId);
      final knownIds = room.messages.map((m) => m.id).toSet();
      final extras = localMessages
          // 'msg-' 前缀行是本地临时 id 时代的脏数据，不进权威流
          .where((m) => !(m['id'] as String).startsWith('msg-'))
          .where((m) => !knownIds.contains(m['id'] as String))
          .map((m) => Message(
                id: m['id'] as String,
                roomId: roomId,
                sender: m['sender'] as String,
                content: m['content'] as String,
                timestamp:
                    DateTime.fromMillisecondsSinceEpoch(m['timestamp'] as int),
              ))
          .toList();
      if (extras.isNotEmpty) {
        final merged = _mergeServerMessages(room.messages, extras);
        _roomManager.upsertRoom(
          room.copyWith(messages: merged),
          moveToTop: false,
        );
      }
    }
  }

  /// 服务端流 + 本地已有消息按 id 去重合并，按时间戳排序。
  /// 同 id 以服务端版本为准（列表在前，覆盖在后）。
  List<Message> _mergeServerMessages(
      List<Message> existing, List<Message> server) {
    final byId = <String, Message>{
      for (final m in existing) m.id: m,
      for (final m in server) m.id: m,
    };
    final merged = byId.values.toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return merged;
  }

  Future<void> _handleLeaveRoom() async {
    if (_currentRoom != null) {
      final roomId = _currentRoom!.id;
      final success = await _roomOperations.leaveRoom(context, roomId);
      if (!success) return;

      CryptoService().clearRoomKey(roomId);
      // 弹出聊天页
      if (mounted) {
        Navigator.of(context).pop();
      }
      return;
    }
    // 正常返回（不是离开房间），只需要 Navigator.pop
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  /// F1-2：从 `Future<void>` 改造为 `Future<UnlockResult>`，让 ChatPage 能根据
  /// ok/err 切换 in-flight → success/error 三阶段反馈（修复用户反馈 bug：
  /// 解锁/保存按钮无任何反馈）。
  ///
  /// 副作用（setState、触觉、音效）保留在 app.dart；ChatPage 不重复触发。
  /// 错误路径不再直接 `ErrorMessages.showErrorSnackBar`，错误文案交给 ChatPage 渲染。
  Future<UnlockResult> _handleUnlock(String roomId) async {
    final result = await _roomOperations.unlockProfile(roomId);
    if (result.ok) {
      // 解锁是决定性事件：重触觉 + 解锁短音
      HapticService.instance.heavy();
      SoundService.instance.playUnlock();
    }
    return result;
  }

  /// F1-2：从 `Future<void>` 改造为 `Future<SaveResult>`。
  ///
  /// 成功路径不再 `ScaffoldMessenger.showSnackBar('保存请求已发送')`，文案统一由
  /// ChatPage 在 in-flight 状态机中渲染（含 forceConfirm/早返回路径的 success/err）。
  /// 节流保留：RoomOperations 是请求层去重的唯一权威。
  Future<SaveResult> _handleSave(String roomId,
      {bool forceConfirm = false}) async {
    return _roomOperations.saveConnection(roomId, true);
  }

  void _handleConfirmDeep(String roomId) {
    _roomOperations.confirmDeepConnection(roomId);
  }

  Future<void> _handleBlock(String roomId) async {
    await _roomOperations.blockUser(context, roomId);
    CryptoService().clearRoomKey(roomId);
    await _handleLeaveRoom();
  }

  Future<void> _handleSaveMoment(String roomId, String content) async {
    await _roomOperations.saveMoment(context, roomId, content);
    HapticService.instance.medium();
  }

  Future<void> _handleResetIdentity() async {
    final stopListeningSuccess = await _stopListeningRegistration();
    if (!stopListeningSuccess) {
      ErrorMessages.showErrorSnackBar(context, '停止收听失败，请稍后重试');
      return;
    }

    final result = await ApiService().resetIdentity();
    if (!result.isSuccess) {
      if (!mounted) return;
      ErrorMessages.showErrorSnackBar(context, ErrorMessages.friendly(result.code, result.message));
      return;
    }

    LocationService().stopLocation();
    WsService().disconnect();
    await PushService().unregisterToken();
    final oldRooms = List<ChatRoom>.from(_rooms);
    for (final room in oldRooms) {
      await StorageService().deleteRoomMessages(room.id);
    }
    CryptoService().clearAllKeys();

    await AuthService().clearAuth();
    resetServerTimeOffset();
    final uuid = AuthService().generateUUID();
    final registerResult = await ApiService().register(uuid);
    if (!registerResult.isSuccess || registerResult.data == null) {
      if (!mounted) return;
      ErrorMessages.showErrorSnackBar(
          context, ErrorMessages.friendly(registerResult.code, registerResult.message));
      return;
    }
    await AuthService().saveAuth(registerResult.data!.token, uuid);
    WsService().connect();
    await _syncServerTime();

    if (!mounted) return;
    setState(() {
      _showProfile = false;
      _activeTab = 'sonar';
    });
    _roomManager.clear();
    _sonarManager.clear();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('匿名身份已重置'), backgroundColor: AppColors.primary),
    );
  }

  void _handleSendMessage(String roomId, String content) async {
    var sendContent = content;
    if (CryptoService().hasSharedKey(roomId)) {
      final encrypted = await CryptoService().encrypt(roomId, content);
      if (encrypted != null) {
        sendContent = encrypted;
      }
    }

    // B13 埋点：发送前记录通道状态，配合 DebugLog 文件定位发送链路断点
    DebugLog().write(
        'Chat send: room=$roomId wsConnected=${WsService().isConnected} encrypted=${sendContent != content}');
    WsService().sendChat(roomId, sendContent);
    final room = _roomManager.findRoom(roomId);
    if (room != null) {
      final msg = Message(
        id: 'msg-${DateTime.now().millisecondsSinceEpoch}',
        roomId: roomId,
        sender: 'me',
        content: content, // 本地显示明文
        timestamp: DateTime.now(),
      );
      // 本地缓存
      StorageService().saveMessage(roomId,
          id: msg.id,
          sender: msg.sender,
          content: msg.content,
          timestamp: msg.timestamp.millisecondsSinceEpoch);
      _roomManager.upsertRoom(
        room.copyWith(messages: [...room.messages, msg]),
        moveToTop: false,
      );
    }
  }

  /// 收听模式开关（2026-11-06 修复用户实锤 bug，勿回退成只改本地状态）。
  ///
  /// 开关是纯标志位，**任何分支都不弹定位授权框**：授权只在启动时（收听开启）和发送声呐时发生。
  /// 服务端只把「收听名单」里的人当作接收方和附近人数的计数对象，所以开关必须同步到服务端：
  /// - 开：翻标志 → 启动定位追踪（只查授权不弹框）→ 用已知网格立即登记；
  ///   还没有网格时等定位回调自动登记，没有授权就只提示一句，等发送声呐授权后自动生效
  /// - 关：**先**请求服务端注销，成功后才关本地、停定位、清附近人数。注销失败就保持开启并提示，
  ///   开关显示必须和服务端真实状态一致——旧版只改本地，服务端名单里一直有你，
  ///   照收别人的脉冲、照样计入别人的「附近 N 人」。
  Future<void> _handleToggleListening(bool value) async {
    if (value) {
      await _sonarManager.toggleListening(true);
      await _startLocationTracking();
      final geohash = LocationService().currentGeohash;
      if (geohash.isNotEmpty) {
        await _startListeningAt(geohash, force: true);
      } else if (!LocationService().isRunning && mounted) {
        ErrorMessages.showSuccessSnackBar(
            context, '收听已开启。暂未获得定位，发送声呐并授权后别人才能搜到你');
      }
      unawaited(_sonarManager.refreshReceivedSonars());
      return;
    }

    final stopped = await _stopListeningRegistration();
    if (!stopped) {
      if (mounted) {
        ErrorMessages.showErrorSnackBar(context, '关闭收听失败，请检查网络后重试');
      }
      return;
    }
    LocationService().stopLocation();
    _nearbyActivityTimer?.cancel();
    if (mounted) {
      setState(() {
        _nearbyCount = 0;
        _blipCount = 0;
        _nearbyLoaded = false;
      });
    }
    await _sonarManager.toggleListening(false);
    DebugLog().write('Listen: silent mode on, unregistered');
  }

  Future<void> _cleanupStaleRooms(List<String> roomIds) async {
    for (final roomId in roomIds) {
      if (_rooms.any((room) => room.id == roomId)) continue;
      debugPrint('[NoiseX] Cleaning stale room: $roomId');
      CryptoService().clearRoomKey(roomId);
      await StorageService().deleteRoomMessages(roomId);
    }
  }

  Future<void> _refreshRooms() async {
    try {
      final result = await ApiService().getRooms();
      if (result.isSuccess && result.data != null) {
        final serverRooms = result.data!;
        // 反追踪兜底：以服务端列表为准清理落盘残留（离线过期 / 进程重启自愈，
        // 与 _cleanupStaleRooms 事件链互补；空列表只清消息不动密钥，防异常误伤）
        final activeRoomIds = serverRooms.map((r) => r.id).toList();
        await StorageService().purgeMessagesExceptRooms(activeRoomIds);
        CryptoService().retainPersistedKeysOnly(activeRoomIds);
        final previousRooms = List<ChatRoom>.from(_rooms);
        final canCleanupStaleRooms =
            hasServerTimeOffset && serverRooms.isNotEmpty;
        final staleRoomIds = canCleanupStaleRooms
            ? computeStaleRoomIds(
                previousRooms
                    .where((room) => room.expiresAt.isBefore(serverNow()))
                    .map((room) => room.id),
                serverRooms.map((room) => room.id),
              )
            : <String>[];
        if (!canCleanupStaleRooms && previousRooms.isNotEmpty) {
          debugPrint(
              '[NoiseX] Skip stale room cleanup: server time unsynced or room list empty');
        }
        final currentRoomId = _currentRoom?.id;
        final currentRoomStale =
            currentRoomId != null && staleRoomIds.contains(currentRoomId);

        final newRooms = serverRooms.map((r) {
          final existingIndex =
              previousRooms.indexWhere((room) => room.id == r.id);
          return ChatRoom(
            id: r.id,
            sonarContent: r.sonarContent,
            signalCode: r.signalCode,
            expiresAt: DateTime.fromMillisecondsSinceEpoch(r.expiresAt),
            createdAt: r.createdAt > 0
                ? DateTime.fromMillisecondsSinceEpoch(r.createdAt)
                : null,
            messages: existingIndex != -1
                ? previousRooms[existingIndex].messages
                : [],
            // D2（2026-11-03 真机双端实测实锤）：列表接口不带对方资料，
            // 重建房间对象时必须透传已有 otherProfile，否则解锁拿到的资料
            // 会被下一次列表刷新（切 Tab/WS 重连）整体抹掉，资料卡回到
            // "TA 还没有留下…"空态
            otherProfile: existingIndex != -1
                ? previousRooms[existingIndex].otherProfile
                : null,
            unlocked: r.unlocked,
            deepConnectionAchieved: r.deepConnectionAchieved,
            deepConnectionConfirmed: r.deepConnectionConfirmed,
            bothDeepConfirmed: r.bothDeepConfirmed,
            savedConnection: r.savedConnection,
            mySaveConfirmed: r.mySaveConfirmed,
            bothSaveConfirmed: r.bothSaveConfirmed,
            lastReadMessageId: r.lastReadMessageId,
            peerReadMessageId: r.peerReadMessageId,
          );
        }).toList();
        _roomManager.syncRooms(newRooms);
        // 服务端重建的消息列表不带 isRead，用对方指针恢复气泡 ✓✓
        for (final r in newRooms) {
          if (r.peerReadMessageId.isNotEmpty) {
            _roomManager.applyPeerReadPointer(r.id, r.peerReadMessageId);
          }
        }
        if (currentRoomStale) {
          _roomManager.setCurrentRoom(null);
        }

        if (currentRoomStale) {
          PushService().setCurrentRoom(null);
        }
        await _cleanupStaleRooms(staleRoomIds);
      }
    } catch (e) {
      debugPrint('[NoiseX] Refresh rooms failed: $e');
    }
  }

  /// 根页系统返回键（B22 修复）。
  /// 鸿蒙端首页按返回的默认行为是应用退到后台（进程保留），而非终止到桌面；
  /// Flutter 默认在根路由触发 SystemNavigator.pop → OHOS embedding 终止 Ability，
  /// 这就是"返回键直接退出 App 到桌面"的根因。OHOS 走自建通道退后台；
  /// 其他平台（Android 默认语义即退出）回落 SystemNavigator.pop。
  Future<void> _handleRootBack() async {
    try {
      final handled = await _systemChannel.invokeMethod<bool>('moveToBackground');
      if (handled == true) return;
    } on MissingPluginException {
      // 非 OHOS 平台无此通道实现
    } catch (e) {
      debugPrint('[NoiseX] moveToBackground failed: $e');
    }
    await SystemNavigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    // 更新柔光模式状态（自动模式时根据时间判断）
    if (_softLightAuto) {
      _softLightEnabled = _isSoftLightTime();
    }

    if (_showSplash) {
      return SplashPage(
        onComplete: () {
          setState(() => _showSplash = false);
          _checkPrivacyGate();
        },
      );
    }

    if (_showPrivacyGate) {
      // 首启协议门：PopScope 已在页面内部拦截返回键，不同意只允许退出应用
      return PrivacyAgreementPage(
        onAgree: () {
          StorageService().setBool(Constants.prefsKeyPrivacyAgreed, true);
          setState(() => _showPrivacyGate = false);
          _checkOnboarding();
        },
        onDisagree: _confirmExitOnDisagree,
      );
    }

    if (_showOnboarding) {
      return OnboardingPage(
        onComplete: () {
          // 标记 onboarding 已完成
          StorageService().setBool('onboarding_completed', true);
          setState(() => _showOnboarding = false);
          _initAfterSplash();
        },
      );
    }

    if (_showProfile) {
      // Profile/Report 是整页 state 替换而非路由 push：系统返回键若不拦截会
      // 直达根路由终止逻辑（B22 同族缺陷）。拦截后等价于 onBack 返回主页
      //（对齐鸿蒙端 navPathStack.push 的返回语义）
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) setState(() => _showProfile = false);
        },
        child: ProfilePage(
          onBack: () => setState(() => _showProfile = false),
          onResetIdentity: _handleResetIdentity,
        ),
      );
    }

    // Scaffold 提供 Material 祖先：SonarPage 的 Switch、全局 Text 都依赖它，
    // 缺失会报 "No Material widget found"（Android/OHOS 双端实锤）
    // 根页返回键 → 退后台（B22，见 _handleRootBack）
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleRootBack();
      },
      child: Scaffold(
      body: Stack(
        children: [
          Column(
            children: [
              // 顶部网络状态条（替代旧的 _isOffline 条；自动监听 WsService.connectionStateStream）
              const ConnectionStatusBar(),
              Expanded(
                child: _buildAnimatedActivePage(context),
              ),
              AppTabBar(
                activeTab: _activeTab,
                onTabChanged: (index) {
                  setState(() => _activeTab = index);
                  _refreshOnTabSwitch(index);
                },
                receiverCount: _receivedSonars.length,
                // 对齐鸿蒙端：角标只统计有未读消息的房间数（非房间总数）
                roomCount: _rooms.where((r) => r.unreadCount > 0).length,
              ),
            ],
          ),
          // 柔光模式蒙版（22:00-06:00 自动启用）
          if (_softLightEnabled) _buildSoftLightOverlay(),
        ],
      ),
      ),
    );
  }

  @override
  void dispose() {
    // 移除状态监听器
    _roomManager.removeListener(_onStateChanged);
    _typingManager.removeListener(_onStateChanged);
    _sonarManager.removeListener(_onStateChanged);
    _roomOperations.removeListener(_onStateChanged);
    _wsEventHandler.removeListener(_onStateChanged);

    // 注销 WS 回调
    _wsEventHandler.unregisterCallbacks();

    // 释放状态管理器资源
    _roomManager.dispose();
    _typingManager.dispose();
    _sonarManager.dispose();
    _roomOperations.dispose();
    _wsEventHandler.dispose();

    // 取消定时器
    _nearbyActivityTimer?.cancel();

    super.dispose();
  }

  /// F3-1：Tab 主体平滑切换。
  ///
  /// reduce-motion 时把 duration 设为 [Duration.zero] 并跳过 transitionBuilder，
  /// 满足无障碍偏好；否则 250ms easeInOutCubic + 微上滑 + 渐显，匹配稳重玻璃风格。
  Widget _buildAnimatedActivePage(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    final transitionDuration =
        reduceMotion ? Duration.zero : AppAnimations.tabActivate;
    return AnimatedSwitcher(
      duration: transitionDuration,
      switchInCurve: AppAnimations.tabSwitchCurve,
      switchOutCurve: AppAnimations.tabSwitchCurve,
      transitionBuilder: (child, anim) {
        if (reduceMotion) return child;
        return FadeTransition(
          opacity: anim,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.02),
              end: Offset.zero,
            ).animate(anim),
            child: child,
          ),
        );
      },
      child: KeyedSubtree(
        key: ValueKey<String>(_activeTab),
        child: _buildActivePage(),
      ),
    );
  }

  Widget _buildActivePage() {
    if (_activeTab == 'sonar') {
      return SonarPage(
        onSonarSent: _handleSonarSent,
        isListening: _isListening,
        onToggleListening: _handleToggleListening,
        onOpenProfile: () => setState(() => _showProfile = true),
        cooldown: _sonarCooldown,
        cooldownTotal: Constants.sonarCooldownSeconds,
        statusBarHeight: _statusBarHeight,
        nearbyCount: _nearbyCount,
        nearbyLoaded: _nearbyLoaded,
        blipCount: _blipCount,
      );
    }
    if (_activeTab == 'receiver') {
      return ReceiverPage(
        sonars: _receivedSonars,
        onAccept: _handleAcceptSonar,
        onIgnore: _handleIgnoreSonar,
        onRefresh: () => _sonarManager.refreshReceivedSonars(),
        // UI 评审 P1：空态行动出口——跳回声呐页
        onGoToSonar: () => setState(() => _activeTab = 'sonar'),
        statusBarHeight: _statusBarHeight,
      );
    }
    return HourglassPage(
      rooms: _rooms,
      onEnterRoom: _handleEnterRoom,
      onRefresh: () async {
        await _refreshRooms();
        // 列表接口不带回消息流：未读角标/预览要靠逐房间补同步才能刷新
        await _syncRoomMessagesForBadges();
      },
      statusBarHeight: _statusBarHeight,
    );
  }

  /// 判断当前时间是否在柔光时段（22:00-06:00）
  bool _isSoftLightTime() {
    final now = DateTime.now();
    final hour = now.hour;
    return hour >= 22 || hour < 6;
  }

  /// 柔光蒙版（琥珀色半透明，减少蓝光）
  Widget _buildSoftLightOverlay() {
    return Positioned.fill(
      child: IgnorePointer(
        child: Container(
          color: const Color(0x1AFFA000), // 琥珀色，10% 不透明度
        ),
      ),
    );
  }
}
