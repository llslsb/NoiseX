import 'dart:io';

/// 联调期文件日志（B13 定位手段）。
///
/// OHOS 真机/模拟器上 debugPrint 会被引擎日志过滤吞掉（hilog 只见引擎日志），
/// WS 断连、发送丢弃这类问题无法从日志侧观测。本工具把关键事件直接落盘到
/// 应用可写目录，用 hdc 拉取即可离线分析：
///
/// ```bash
/// hdc shell "cat /data/app/el2/100/base/com.lls.noisex/haps/entry/files/noisex_debug.log"
/// ```
///
/// 定位完成后可整体移除；所有写入都吞异常，绝不影响主流程。
class DebugLog {
  static final DebugLog _instance = DebugLog._();
  factory DebugLog() => _instance;
  DebugLog._();

  File? _file;
  final List<String> _pending = [];
  bool _broken = false;
  bool _initializing = false;
  // 串行化写盘：无序的并发 append 会互相覆盖导致丢行（联调时实测丢日志）
  Future<void> _writeChain = Future.value();

  /// 候选目录：OHOS 应用沙箱 files 目录（模拟器上 hdc 有读权限），系统临时目录兜底。
  static List<String> get _candidateDirs => [
        '/data/app/el2/100/base/com.lls.noisex/haps/entry/files',
        '/data/storage/el2/base/haps/entry/files',
        Directory.systemTemp.path,
      ];

  void write(String message) {
    if (_broken) return;
    _pending.add('${DateTime.now().toIso8601String()} $message');
    if (_file != null) {
      _writePending();
    } else if (!_initializing) {
      _init();
    }
  }

  Future<void> _init() async {
    _initializing = true;
    try {
      for (final dir in _candidateDirs) {
        try {
          final d = Directory(dir);
          if (!await d.exists()) continue;
          final f = File('${d.path}/noisex_debug.log');
          await f.writeAsString(
              '=== session ${DateTime.now().toIso8601String()} ===\n',
              mode: FileMode.append);
          _file = f;
          break;
        } catch (_) {
          continue;
        }
      }
    } finally {
      _initializing = false;
      if (_file == null) {
        _broken = true;
      } else {
        _writePending();
      }
    }
  }

  void _writePending() {
    final f = _file;
    if (f == null || _pending.isEmpty) return;
    final text = '${_pending.join('\n')}\n';
    _pending.clear();
    _writeChain = _writeChain
        .then((_) => f.writeAsString(text, mode: FileMode.append))
        .then((_) => f)
        .catchError((_) => f);
  }
}
