import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import '../models/constants.dart';

/// 本地存储服务
/// Preferences 键值存储 + SQLite 消息缓存
class StorageService {
  static final StorageService _instance = StorageService._();
  factory StorageService() => _instance;
  StorageService._();

  SharedPreferences? _prefs;
  Database? _db;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    await _initDb();
    await _cleanExpiredMessages();
  }

  Future<void> _initDb() async {
    // sqflite 目前没有 OHOS 平台实现：无实现的环境下降级为"无本地缓存"模式，
    // 不阻塞启动（消息实时收发不受影响，仅离线缓存缺失）
    try {
      _db = await openDatabase(
        Constants.dbName,
        version: 2,
        onCreate: (db, version) async {
          await db.execute('''
          CREATE TABLE messages (
            id TEXT PRIMARY KEY,
            room_id TEXT NOT NULL,
            sender TEXT NOT NULL,
            content TEXT NOT NULL,
            timestamp INTEGER NOT NULL,
            is_read INTEGER DEFAULT 0
          )
        ''');
          await db.execute(
            'CREATE INDEX idx_messages_room ON messages(room_id)',
          );
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 2) {
            await db.execute('ALTER TABLE messages ADD COLUMN is_read INTEGER DEFAULT 0');
          }
        },
      );
    } catch (_) {
      _db = null;
    }
  }

  // --- Preferences ---

  String getString(String key, {String defaultValue = ''}) {
    return _prefs?.getString(key) ?? defaultValue;
  }

  Future<bool> setString(String key, String value) async {
    return await _prefs?.setString(key, value) ?? false;
  }

  int getInt(String key, {int defaultValue = 0}) {
    return _prefs?.getInt(key) ?? defaultValue;
  }

  Future<bool> setInt(String key, int value) async {
    return await _prefs?.setInt(key, value) ?? false;
  }

  bool getBool(String key, {bool defaultValue = false}) {
    return _prefs?.getBool(key) ?? defaultValue;
  }

  Future<bool> setBool(String key, bool value) async {
    return await _prefs?.setBool(key, value) ?? false;
  }

  Future<bool> remove(String key) async {
    return await _prefs?.remove(key) ?? false;
  }

  // --- SQLite 消息缓存 ---

  /// 保存消息到本地数据库
  Future<void> saveMessage(String roomId, {
    required String id,
    required String sender,
    required String content,
    required int timestamp,
  }) async {
    if (_db == null) return;
    try {
      await _db!.insert(
        'messages',
        {
          'id': id,
          'room_id': roomId,
          'sender': sender,
          'content': content,
          'timestamp': timestamp,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (_) {}
  }

  /// 从本地数据库获取消息
  Future<List<Map<String, dynamic>>> getMessages(String roomId, {
    int limit = 50,
    int offset = 0,
  }) async {
    if (_db == null) return [];
    try {
      return await _db!.query(
        'messages',
        where: 'room_id = ?',
        whereArgs: [roomId],
        orderBy: 'timestamp ASC',
        limit: limit,
        offset: offset,
      );
    } catch (_) {
      return [];
    }
  }

  /// 删除房间的本地消息
  Future<void> deleteRoomMessages(String roomId) async {
    if (_db == null) return;
    try {
      await _db!.delete(
        'messages',
        where: 'room_id = ?',
        whereArgs: [roomId],
      );
    } catch (_) {}
  }

  /// 用服务端权威流整体替换某房间的本地缓存行（事务）。
  ///
  /// 自愈用途：历史 bug 时代缓存里混入过脏行（own 消息存成 other、
  /// 'msg-' 本地 id 与服务端流 id 双份），靠服务端流回写一次洗净。
  /// 仅在 REST 成功拿到完整消息流后调用。
  Future<void> replaceRoomMessages(
      String roomId, List<Map<String, dynamic>> rows) async {
    if (_db == null) return;
    try {
      await _db!.transaction((txn) async {
        await txn.delete(
          'messages',
          where: 'room_id = ?',
          whereArgs: [roomId],
        );
        for (final row in rows) {
          await txn.insert(
            'messages',
            {
              'id': row['id'],
              'room_id': roomId,
              'sender': row['sender'],
              'content': row['content'],
              'timestamp': row['timestamp'],
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      });
    } catch (_) {}
  }

  /// 清除不属于任何活跃房间的缓存消息（反追踪兜底：不保留历史）。
  ///
  /// 覆盖房间过期事件链路之外的残留：离线过期、进程重启后内存列表为空等。
  /// 列表为空时全清——空列表只可能意味着全部房间已过期；若为服务端异常，
  /// 活跃房间的历史仍可由服务端 Redis（72h TTL）重新拉取解密恢复。
  Future<int> purgeMessagesExceptRooms(List<String> activeRoomIds) async {
    if (_db == null) return 0;
    try {
      if (activeRoomIds.isEmpty) {
        return await _db!.delete('messages');
      }
      final placeholders = List.filled(activeRoomIds.length, '?').join(',');
      return await _db!.delete(
        'messages',
        where: 'room_id NOT IN ($placeholders)',
        whereArgs: activeRoomIds,
      );
    } catch (_) {
      return 0;
    }
  }

  Future<void> _cleanExpiredMessages() async {
    if (_db == null) return;
    try {
      final cutoff = DateTime.now().subtract(const Duration(hours: 72)).millisecondsSinceEpoch;
      await _db!.delete(
        'messages',
        where: 'timestamp < ?',
        whereArgs: [cutoff],
      );
    } catch (_) {}
  }
}
