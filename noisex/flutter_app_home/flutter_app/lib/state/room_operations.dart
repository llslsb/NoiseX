import 'dart:async';
import 'package:flutter/material.dart';
import '../models/api_types.dart';
import '../models/chat_room.dart';
import '../models/message.dart';
import '../services/api_service.dart';
import '../services/debug_log.dart';
import '../services/storage_service.dart';
import '../services/crypto_service.dart';
import '../services/push_service.dart';
import '../services/ws_service.dart';
import '../utils/error_messages.dart';
import 'room_manager.dart';

/// 房间操作管理器
///
/// 职责：
/// - 进入/离开房间
/// - 解锁资料
/// - 保存连接
/// - 深度交流确认
/// - 举报/拉黑
/// - 保存片段
class RoomOperations extends ChangeNotifier {
  final RoomManager _roomManager;
  final Set<String> _saveConfirmingRoomIds = <String>{};
  final Set<String> _unlockConfirmingRoomIds = <String>{};

  RoomOperations(this._roomManager);

  /// 正在确认保存的房间集合
  bool isSaveConfirming(String roomId) => _saveConfirmingRoomIds.contains(roomId);

  /// 正在确认解锁的房间集合
  bool isUnlockConfirming(String roomId) => _unlockConfirmingRoomIds.contains(roomId);

  /// 进入房间
  Future<void> enterRoom(BuildContext context, String roomId) async {
    final room = _roomManager.findRoom(roomId);
    if (room == null) return;

    PushService().setCurrentRoom(roomId);
    _roomManager.setCurrentRoom(room);

    // 加载历史消息
    await _loadRoomMessages(context, roomId);
  }

  /// 加载房间历史消息
  ///
  /// 2026-11-02 修复（与 app.dart _reloadRoomFromServer 同款缺陷的第二份
  /// 拷贝）：本方法回退分支曾把 SQLite 旧缓存【整表替换】内存——缓存里
  /// 混着历史 bug 时代的脏行（同 id 海量重复 + own 消息存成 other），进入
  /// 聊天页瞬间未读徽标被顶成幻影值（实测 96）。现改为：成功路径按 id
  /// 去重合并 + 回写缓存自愈；失败路径只补漏，绝不整表替换；sender 从
  /// 服务端 UUID 正确映射 me/other（原样透传会让所有消息都算"对方"）。
  Future<void> _loadRoomMessages(BuildContext context, String roomId) async {
    try {
      // B18：进入房间发现既无共享密钥也无临时对（清数据/重装场景）时
      // 主动发起 E2EE 重协商；对方（密钥持有方）会以新对回应，
      // 双方派生新密钥恢复加密。对方离线则等其下次在线/进房时收敛。
      if (!CryptoService().hasSharedKey(roomId) &&
          !CryptoService().hasKeyPair(roomId)) {
        final pubKey = await CryptoService().generateKeyPair(roomId);
        if (pubKey.isNotEmpty) {
          WsService().sendKeyExchange(roomId, pubKey);
        }
      }

      final result = await ApiService().getMessages(roomId);
      if (result.isSuccess && result.data != null) {
        // B16：服务端存的是 E2EE 密文（服务端无法解密），本地有共享密钥时
        // 必须先解密再渲染；解密失败的条目保留原文（对端密钥未就绪的明文）
        final hasKey = CryptoService().hasSharedKey(roomId);
        final messages = <Message>[];
        for (final m in result.data!.messages) {
          var content = m.content;
          if (hasKey) {
            final decrypted = await CryptoService().decrypt(roomId, content);
            if (decrypted != null) content = decrypted;
          }
          messages.add(Message(
            id: m.id,
            roomId: roomId,
            // 后端 getMessages 已按请求方把 sender 归一化成 "me"/"other"
            // （ChatService.java: sender.equals(userId) ? "me" : "other"），
            // 直接透传；旧版拿它跟 UUID 比较恒为 false，每次进房合并把
            // 自己的消息全部翻成"对方"（对号消失/气泡跑到左边，2026-11-03 实锤）
            sender: m.sender == 'me' ? 'me' : 'other',
            content: content,
            timestamp: DateTime.fromMillisecondsSinceEpoch(m.timestamp),
          ));
        }
        final existing = _roomManager.findRoom(roomId);
        if (existing != null) {
          final merged = <String, Message>{
            for (final m in existing.messages) m.id: m,
            for (final m in messages) m.id: m,
          }.values.toList()
            ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
          _roomManager.upsertRoom(
            existing.copyWith(messages: merged),
            moveToTop: false,
          );
          // 与 app.dart._reloadRoomFromServer 同款：REST 行全新 isRead=false，
          // 合并后必须补应用对方已读指针，否则重进后自己的消息永远单勾 ✓
          _roomManager.applyPeerReadPointer(roomId, existing.peerReadMessageId);
        }
        // 缓存自愈：服务端权威流回写 SQLite，洗净历史脏行
        await StorageService().replaceRoomMessages(
          roomId,
          messages
              .map((m) => <String, dynamic>{
                    'id': m.id,
                    'sender': m.sender,
                    'content': m.content,
                    'timestamp': m.timestamp.millisecondsSinceEpoch,
                  })
              .toList(),
        );
      }
    } catch (e) {
      debugPrint('[NoiseX] Load messages failed, merging cache extras: $e');
      final room = _roomManager.findRoom(roomId);
      if (room == null) return;
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
        final merged = <String, Message>{
          for (final m in room.messages) m.id: m,
          for (final m in extras) m.id: m,
        }.values.toList()
          ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
        _roomManager.upsertRoom(
          room.copyWith(messages: merged),
          moveToTop: false,
        );
      }
    }
  }

  /// 离开房间
  Future<bool> leaveRoom(BuildContext context, String roomId) async {
    final result = await ApiService().leaveRoom(roomId);
    if (!result.isSuccess) {
      if (context.mounted) {
        final msg = ErrorMessages.friendly(result.code, result.message);
        ErrorMessages.showErrorSnackBar(context, msg);
      }
      return false;
    }

    StorageService().deleteRoomMessages(roomId);
    _roomManager.removeRoom(roomId);
    PushService().setCurrentRoom(null);

    return true;
  }

  /// 解锁资料
  Future<UnlockResult> unlockProfile(String roomId) async {
    _unlockConfirmingRoomIds.add(roomId);
    notifyListeners();

    try {
      final result = await ApiService().unlockProfile(roomId);
      // D2 插桩：解锁链路三段日志（响应/入参/合并后回读），定位资料卡空态
      DebugLog().write(
          '[unlock] ok=${result.isSuccess} code=${result.code} '
          'unlocked=${result.data?.unlocked} '
          'sig=${result.data?.profile?.signature}');
      if (result.isSuccess && result.data != null && result.data!.unlocked) {
        final room = _roomManager.findRoom(roomId);
        if (room != null) {
          final updatedRoom = room.copyWith(
            unlocked: true,
            otherProfile: result.data!.profile != null
                ? UserProfile(
                    signature: result.data!.profile!.signature,
                    city: result.data!.profile!.city,
                    contact: result.data!.profile!.contact,
                  )
                : null,
          );
          _roomManager.upsertRoom(updatedRoom, moveToTop: false);
          DebugLog().write(
              '[unlock] upserted otherProfile=${_roomManager.findRoom(roomId)?.otherProfile?.signature}');
        } else {
          DebugLog().write('[unlock] room not found in manager');
        }
        return UnlockResult.ok(result.data!.profile);
      } else {
        return UnlockResult.err(ErrorMessages.friendly(result.code, result.message));
      }
    } finally {
      _unlockConfirmingRoomIds.remove(roomId);
      notifyListeners();
    }
  }

  /// 保存连接
  Future<SaveResult> saveConnection(String roomId, bool agree, {bool forceConfirm = false}) async {
    _saveConfirmingRoomIds.add(roomId);
    notifyListeners();

    try {
      final result = await ApiService().saveConnection(roomId, agree: agree);
      if (result.isSuccess) {
        final room = _roomManager.findRoom(roomId);
        if (room != null) {
          // 简单逻辑：agree 为 true 时，至少我已确认；是否双方确认由后续事件同步
          final updatedRoom = room.copyWith(
            savedConnection: agree,
            mySaveConfirmed: agree,
            bothSaveConfirmed: false, // 等待对方确认
          );
          _roomManager.upsertRoom(updatedRoom, moveToTop: false);
        }
        return SaveResult.ok();
      } else {
        return SaveResult.err(ErrorMessages.friendly(result.code, result.message));
      }
    } finally {
      _saveConfirmingRoomIds.remove(roomId);
      notifyListeners();
    }
  }

  /// 确认深度交流
  void confirmDeepConnection(String roomId) {
    WsService().sendDeepConfirm(roomId);
    final room = _roomManager.findRoom(roomId);
    if (room != null) {
      final updatedRoom = room.copyWith(
        deepConnectionConfirmed: true,
      );
      _roomManager.upsertRoom(updatedRoom, moveToTop: false);
    }
  }

  /// 举报房间
  Future<bool> reportRoom(BuildContext context, String roomId,
      {String? reason, String? phoneNumber}) async {
    final result = await ApiService().reportRoom(roomId, reason ?? '', phoneNumber: phoneNumber);
    if (result.isSuccess) {
      if (context.mounted) {
        ErrorMessages.showSuccessSnackBar(context, '举报已提交');
      }
      return true;
    } else {
      if (context.mounted) {
        final msg = ErrorMessages.friendly(result.code, result.message);
        ErrorMessages.showErrorSnackBar(context, msg);
      }
      return false;
    }
  }

  /// 拉黑用户
  Future<bool> blockUser(BuildContext context, String roomId) async {
    final result = await ApiService().blockUser(roomId);
    if (result.isSuccess) {
      // D-M9-1：blocked 标记让 RoomManager 拒收该房间的后续 upsert
      // （服务端列表不过滤已拉黑房间，刷新会把房间"复活"）
      _roomManager.removeRoom(roomId, blocked: true);
      if (context.mounted) {
        ErrorMessages.showSuccessSnackBar(context, '已屏蔽该用户');
      }
      return true;
    } else {
      if (context.mounted) {
        final msg = ErrorMessages.friendly(result.code, result.message);
        ErrorMessages.showErrorSnackBar(context, msg);
      }
      return false;
    }
  }

  /// 保存对话片段
  Future<bool> saveMoment(BuildContext context, String roomId, String content) async {
    final result = await ApiService().saveMoment(roomId, content);
    if (result.isSuccess) {
      if (context.mounted) {
        ErrorMessages.showSuccessSnackBar(context, '片段已保存');
      }
      return true;
    } else {
      if (context.mounted) {
        final msg = ErrorMessages.friendly(result.code, result.message);
        ErrorMessages.showErrorSnackBar(context, msg);
      }
      return false;
    }
  }
}
