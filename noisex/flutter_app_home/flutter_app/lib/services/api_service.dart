import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import '../models/api_types.dart';
import '../models/constants.dart';
import 'auth_service.dart';
import 'dart:io';

class ApiService {
  static final ApiService _instance = ApiService._();
  factory ApiService() => _instance;
  ApiService._();

  final AuthService _auth = AuthService();

  static final http.Client _client = IOClient(HttpClient()
    ..connectionTimeout = const Duration(seconds: 10)
    ..idleTimeout = const Duration(seconds: 30));

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (_auth.jwt != null) 'Authorization': 'Bearer ${_auth.jwt}',
      };

  Future<ApiResponse<AuthData>> register(String uuid) async {
    final response = await _client.post(
      Uri.parse('${Constants.apiBaseUrl}/api/auth/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'anonymousUuid': uuid}),
    );
    return _parseResponse(response, (data) => AuthData(
          token: data['token'] as String,
          expiresIn: data['expiresIn'] as int? ?? 86400,
        ));
  }

  Future<ApiResponse<AuthData>> refreshToken() async {
    final response = await _client.post(
      Uri.parse('${Constants.apiBaseUrl}/api/auth/refresh'),
      headers: _headers,
    );
    return _parseResponse(response, (data) => AuthData(
          token: data['token'] as String,
          expiresIn: data['expiresIn'] as int? ?? 86400,
        ));
  }

  Future<ApiResponse<SonarSendData>> sendSonar(String content, String geohash) async {
    return _withAutoRefresh(() async {
      final body = <String, dynamic>{'content': content, 'geohash': geohash};
      final response = await _client.post(
        Uri.parse('${Constants.apiBaseUrl}/api/sonar'),
        headers: _headers,
        body: jsonEncode(body),
      );
      return _parseResponse(response, (data) => SonarSendData(
            sonarId: data['sonarId'] as String,
            remainingQuota: data['cooldownRemaining'] as int? ?? 0,
          ));
    });
  }

  Future<ApiResponse<List<ReceivedSonarData>>> getReceivedSonars() async {
    return _withAutoRefresh(() async {
      final response = await _client.get(
        Uri.parse('${Constants.apiBaseUrl}/api/sonar/received'),
        headers: _headers,
      );
      return _parseResponse(response, (data) {
        // 服务端 ApiResponse.success(List) 的 data 就是数组本身
        // （鸿蒙端 resp.data 直取同款；旧版误取 data['sonars'] 永远为空，联调缺陷 B9）
        final list = (data as List?) ?? [];
        return list.map((e) => ReceivedSonarData(
              id: e['id'] as String,
              content: e['content'] as String? ?? '',
              distance: e['distance'] as String? ?? '',
              timestamp: e['timestamp'] as int? ?? 0,
            )).toList();
      });
    });
  }

  Future<ApiResponse<AcceptSonarData>> acceptSonar(String sonarId) async {
    return _withAutoRefresh(() async {
      final response = await _client.post(
        Uri.parse('${Constants.apiBaseUrl}/api/sonar/$sonarId/accept'),
        headers: _headers,
      );
      return _parseResponse(response, (data) => AcceptSonarData(
            roomId: data['roomId'] as String,
            signalCode: data['signalCode'] as String? ?? '',
            sonarContent: data['sonarContent'] as String? ?? '',
            expiresAt: data['expiresAt'] as int? ?? 0,
          ));
    });
  }

  Future<ApiResponse<void>> ignoreSonar(String sonarId) async {
    return _withAutoRefresh(() async {
      final response = await _client.post(
        Uri.parse('${Constants.apiBaseUrl}/api/sonar/$sonarId/ignore'),
        headers: _headers,
      );
      return _parseResponse(response, (_) {});
    });
  }

  Future<ApiResponse<void>> startListening(String geohash) async {
    return _withAutoRefresh(() async {
      final response = await _client.post(
        Uri.parse('${Constants.apiBaseUrl}/api/sonar/listen?geohash=${Uri.encodeQueryComponent(geohash)}'),
        headers: _headers,
      );
      return _parseResponse(response, (_) {});
    });
  }

  Future<ApiResponse<void>> stopListening(String geohash) async {
    return _withAutoRefresh(() async {
      final response = await _client.post(
        Uri.parse('${Constants.apiBaseUrl}/api/sonar/unlisten?geohash=${Uri.encodeQueryComponent(geohash)}'),
        headers: _headers,
      );
      return _parseResponse(response, (_) {});
    });
  }

  Future<ApiResponse<ServerTimeData>> getServerTime() async {
    return _withAutoRefresh(() async {
      final response = await _client.get(
        Uri.parse('${Constants.apiBaseUrl}/api/time'),
        headers: _headers,
      );
      return _parseResponse(response, (data) => ServerTimeData(
            serverTime: data['serverTime'] as int? ?? 0,
          ));
    });
  }

  Future<ApiResponse<List<RoomData>>> getRooms() async {
    return _withAutoRefresh(() async {
      final response = await _client.get(
        Uri.parse('${Constants.apiBaseUrl}/api/rooms'),
        headers: _headers,
      );
      return _parseResponse(response, (data) {
        // 服务端 ApiResponse.success(List) 的 data 就是数组本身
        // （鸿蒙端同款；旧版误取 data['rooms'] 永远为空，联调缺陷 B10）
        final list = (data as List?) ?? [];
        return list.map((e) => _parseRoomData(e)).toList();
      });
    });
  }

  Future<ApiResponse<RoomData>> getRoom(String roomId) async {
    return _withAutoRefresh(() async {
      final response = await _client.get(
        Uri.parse('${Constants.apiBaseUrl}/api/rooms/$roomId'),
        headers: _headers,
      );
      return _parseResponse(response, (data) => _parseRoomData(data));
    });
  }

  Future<ApiResponse<MessagesData>> getMessages(String roomId, {int offset = 0, int limit = 50}) async {
    return _withAutoRefresh(() async {
      final url = '${Constants.apiBaseUrl}/api/rooms/$roomId/messages?offset=$offset&limit=$limit';
      final response = await _client.get(Uri.parse(url), headers: _headers);
      return _parseResponse(response, (data) {
        final list = (data['messages'] as List?) ?? [];
        final messages = list.map((e) => MessageData(
              id: e['id'] as String,
              sender: e['sender'] as String? ?? '',
              content: e['content'] as String,
              timestamp: e['timestamp'] as int? ?? 0,
            )).toList();
        return MessagesData(
          messages: messages,
          hasMore: data['hasMore'] as bool? ?? false,
        );
      });
    });
  }

  Future<ApiResponse<UnlockData>> unlockProfile(String roomId) async {
    return _withAutoRefresh(() async {
      final response = await _client.post(
        Uri.parse('${Constants.apiBaseUrl}/api/rooms/$roomId/unlock'),
        headers: _headers,
      );
      return _parseResponse(response, (data) => UnlockData(
            unlocked: data['unlocked'] as bool? ?? true,
            profile: data['profile'] != null
                ? ProfileData(
                    signature: data['profile']['signature'] as String? ?? '',
                    city: data['profile']['city'] as String? ?? '',
                    contact: data['profile']['contact'] as String? ?? '',
                  )
                : null,
          ));
    });
  }

  Future<ApiResponse<SaveConnectionData>> saveConnection(String roomId, {bool agree = true}) async {
    return _withAutoRefresh(() async {
      final response = await _client.post(
        Uri.parse('${Constants.apiBaseUrl}/api/rooms/$roomId/save'),
        headers: _headers,
        body: jsonEncode({'agree': agree}),
      );
      return _parseResponse(response, (data) => SaveConnectionData(
            status: data['status'] as String? ?? 'saved',
            message: data['message'] as String? ?? '',
          ));
    });
  }

  Future<ApiResponse<void>> leaveRoom(String roomId) async {
    return _withAutoRefresh(() async {
      final response = await _client.post(
        Uri.parse('${Constants.apiBaseUrl}/api/rooms/$roomId/leave'),
        headers: _headers,
      );
      return _parseResponse(response, (_) {});
    });
  }

  Future<ApiResponse<void>> markRead(String roomId, String messageId) async {
    return _withAutoRefresh(() async {
      final response = await _client.put(
        Uri.parse('${Constants.apiBaseUrl}/api/rooms/$roomId/read?messageId=${Uri.encodeQueryComponent(messageId)}'),
        headers: _headers,
      );
      return _parseResponse(response, (_) {});
    });
  }

  Future<ApiResponse<void>> blockUser(String roomId) async {
    return _withAutoRefresh(() async {
      final response = await _client.post(
        Uri.parse('${Constants.apiBaseUrl}/api/rooms/$roomId/block'),
        headers: _headers,
      );
      return _parseResponse(response, (_) {});
    });
  }

  Future<ApiResponse<List<String>>> getBlockedList() async {
    return _withAutoRefresh(() async {
      final response = await _client.get(
        Uri.parse('${Constants.apiBaseUrl}/api/blocks'),
        headers: _headers,
      );
      return _parseResponse(response, (data) {
        final list = (data as List?) ?? [];
        return list.map((e) => e.toString()).toList();
      });
    });
  }

  Future<ApiResponse<void>> unblockUser(String blockedUserId) async {
    return _withAutoRefresh(() async {
      final response = await _client.delete(
        Uri.parse('${Constants.apiBaseUrl}/api/blocks/${Uri.encodeComponent(blockedUserId)}'),
        headers: _headers,
      );
      return _parseResponse(response, (_) {});
    });
  }

  Future<ApiResponse<ProfileData>> getProfile() async {
    return _withAutoRefresh(() async {
      final response = await _client.get(
        Uri.parse('${Constants.apiBaseUrl}/api/profile'),
        headers: _headers,
      );
      return _parseResponse(response, (data) => ProfileData(
            signature: data['signature'] as String? ?? '',
            city: data['city'] as String? ?? '',
            contact: data['contact'] as String? ?? '',
          ));
    });
  }

  Future<ApiResponse<void>> updateProfile({String? signature, String? city, String? contact}) async {
    return _withAutoRefresh(() async {
      final body = <String, dynamic>{};
      if (signature != null) body['signature'] = signature;
      if (city != null) body['city'] = city;
      if (contact != null) body['contact'] = contact;
      final response = await _client.put(
        Uri.parse('${Constants.apiBaseUrl}/api/profile'),
        headers: _headers,
        body: jsonEncode(body),
      );
      return _parseResponse(response, (_) {});
    });
  }

  Future<ApiResponse<void>> resetIdentity() async {
    return _withAutoRefresh(() async {
      final response = await _client.delete(
        Uri.parse('${Constants.apiBaseUrl}/api/profile/reset'),
        headers: _headers,
      );
      return _parseResponse(response, (_) {});
    });
  }

  Future<ApiResponse<ReportData>> reportRoom(String roomId, String reason, {String? phoneNumber}) async {
    return _withAutoRefresh(() async {
      final body = <String, dynamic>{'roomId': roomId, 'reason': reason};
      if (phoneNumber != null) body['phoneNumber'] = phoneNumber;
      final response = await _client.post(
        Uri.parse('${Constants.apiBaseUrl}/api/report'),
        headers: _headers,
        body: jsonEncode(body),
      );
      return _parseResponse(response, (data) => ReportData(reportId: data['reportId'] as String? ?? ''));
    });
  }

  Future<ApiResponse<void>> registerPushToken(String pushToken, {String channel = 'hms'}) async {
    return _withAutoRefresh(() async {
      final response = await _client.post(
        Uri.parse('${Constants.apiBaseUrl}/api/push/register?pushToken=${Uri.encodeQueryComponent(pushToken)}&channel=$channel'),
        headers: _headers,
      );
      return _parseResponse(response, (_) {});
    });
  }

  Future<ApiResponse<void>> unregisterPushToken() async {
    return _withAutoRefresh(() async {
      final response = await _client.delete(
        Uri.parse('${Constants.apiBaseUrl}/api/push/token'),
        headers: _headers,
      );
      return _parseResponse(response, (_) {});
    });
  }

  Future<ApiResponse<SavedMomentData>> saveMoment(String roomId, String content) async {
    return _withAutoRefresh(() async {
      final response = await _client.post(
        Uri.parse('${Constants.apiBaseUrl}/api/moments'),
        headers: _headers,
        body: jsonEncode({'roomId': roomId, 'content': content}),
      );
      return _parseResponse(response, (data) => SavedMomentData(
            id: data['id'] as String? ?? '',
            roomId: data['roomId'] as String? ?? '',
            content: content,
            createdAt: DateTime.now().millisecondsSinceEpoch,
          ));
    });
  }

  Future<ApiResponse<List<SavedMomentData>>> getSavedMoments() async {
    return _withAutoRefresh(() async {
      final response = await _client.get(
        Uri.parse('${Constants.apiBaseUrl}/api/moments'),
        headers: _headers,
      );
      return _parseResponse(response, (data) {
        final list = (data as List?) ?? [];
        return list.map((e) => SavedMomentData(
              id: e['id'] as String? ?? '',
              roomId: e['roomId'] as String? ?? '',
              content: e['content'] as String? ?? '',
              createdAt: e['createdAt'] as int? ?? 0,
            )).toList();
      });
    });
  }

  /// 查询附近活跃用户数（用于雷达 blip 真实化）。
  /// [geohash] 精度必须为 6 字符，与服务端 @Size 约束一致。
  Future<ApiResponse<NearbyActivityData>> getNearbyActivity(String geohash) async {
    return _withAutoRefresh(() async {
      final response = await _client.get(
        Uri.parse(
            '${Constants.apiBaseUrl}/api/sonar/nearby-activity?geohash=${Uri.encodeQueryComponent(geohash)}'),
        headers: _headers,
      );
      return _parseResponse(response, (data) => NearbyActivityData(
            nearbyCount: data['nearbyCount'] as int? ?? 0,
            blipCount: data['blipCount'] as int? ?? 0,
          ));
    });
  }

  Future<ApiResponse<T>> _withAutoRefresh<T>(
    Future<ApiResponse<T>> Function() request,
  ) async {
    final result = await request();
    if (result.code == 40101 || result.code == 40102) {
      final refreshResult = await refreshToken();
      if (refreshResult.isSuccess && refreshResult.data != null) {
        await _auth.saveAuth(refreshResult.data!.token, _auth.userId ?? '');
        return request();
      }
    }
    return result;
  }

  RoomData _parseRoomData(dynamic e) {
    return RoomData(
      id: e['id'] as String,
      signalCode: e['signalCode'] as String? ?? '',
      sonarContent: e['sonarContent'] as String? ?? '',
      lastMessage: e['lastMessage'] != null
          ? MessageData(
              id: '',
              sender: e['lastMessage']['sender'] as String? ?? '',
              content: e['lastMessage']['content'] as String? ?? '',
              timestamp: e['lastMessage']['timestamp'] as int? ?? 0,
            )
          : null,
      expiresAt: e['expiresAt'] as int? ?? 0,
      createdAt: e['createdAt'] as int? ?? 0,
      unlocked: e['unlocked'] as bool? ?? false,
      deepConnectionAchieved: e['deepConnectionAchieved'] as bool? ?? false,
      deepConnectionConfirmed: e['deepConnectionConfirmed'] as bool? ?? false,
      bothDeepConfirmed: e['bothDeepConfirmed'] as bool? ?? e['bothConfirmed'] as bool? ?? false,
      savedConnection: e['savedConnection'] as bool? ?? e['bothSaveConfirmed'] as bool? ?? false,
      mySaveConfirmed: e['mySaveConfirmed'] as bool? ?? e['saveConnectionConfirmed'] as bool? ?? e['saveConfirmed'] as bool? ?? false,
      bothSaveConfirmed: e['bothSaveConfirmed'] as bool? ?? false,
      messageCount: e['messageCount'] as int? ?? 0,
      lastReadMessageId: e['lastReadMessageId'] as String? ?? '',
      peerReadMessageId: e['peerReadMessageId'] as String? ?? '',
    );
  }

  ApiResponse<T> _parseResponse<T>(http.Response response, T Function(dynamic)? parser) {
    if (response.statusCode != 200 && response.statusCode != 201) {
      try {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        return ApiResponse(
          code: json['code'] as int? ?? -1,
          message: json['message'] as String? ?? '请求失败 (${response.statusCode})',
        );
      } catch (_) {
        return ApiResponse(code: -1, message: '请求失败 (${response.statusCode})');
      }
    }
    try {
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final code = json['code'] as int? ?? 0;
      if (code != 0) {
        return ApiResponse(code: code, message: json['message'] as String? ?? '请求失败');
      }
      if (parser == null || json['data'] == null) {
        return ApiResponse(code: 0);
      }
      return ApiResponse(code: 0, data: parser(json['data']));
    } catch (_) {
      return ApiResponse(code: -1, message: '解析响应失败');
    }
  }
}
