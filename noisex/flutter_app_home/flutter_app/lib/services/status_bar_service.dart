/// 状态栏高度服务
/// 与鸿蒙端 @StorageProp('statusBarHeight') 对齐
class StatusBarService {
  static final StatusBarService _instance = StatusBarService._();
  factory StatusBarService() => _instance;
  StatusBarService._();

  double _height = 0;

  /// 获取状态栏高度（逻辑像素）
  double get height => _height;

  /// 更新状态栏高度（由 MainPage.didChangeDependencies 调用）
  void update(double topPadding) {
    _height = topPadding > 0 ? topPadding : 48;
  }
}
