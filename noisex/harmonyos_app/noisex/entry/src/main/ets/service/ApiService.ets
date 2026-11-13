import { http } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { AuthService } from './AuthService';
import { Logger } from '../common/Logger';
import { ApiBusinessError } from '../common/ApiErrorMessages';
import { Constants } from '../model/Constants';
import {
  ApiResponse, ServerTimeData, AuthData, SonarSendData, ReceivedSonarData,
  AcceptSonarData, RoomData, MessagesData, UnlockData,
  ProfileData, SaveConnectionData, ReportData, SavedMomentData,
  RegisterRequest, SendSonarRequest, SaveConnectionRequestBody,
  UpdateProfileRequest, ReportRequest, SaveMomentRequest, NearbyActivityData
} from '../model/ApiTypes';

// HTTP API 调用封装
export class ApiService {
  private static instance: ApiService;

  private constructor() {}

  public static getInstance(): ApiService {
    if (!ApiService.instance) {
      ApiService.instance = new ApiService();
    }
    return ApiService.instance;
  }

  // ========== 系统 ==========

  public async getServerTime(): Promise<number> {
    const resp: ApiResponse<ServerTimeData> =
      await this.get<ApiResponse<ServerTimeData>>('/api/time');
    if (resp.data !== null) {
      return resp.data.serverTime;
    }
    throw new Error('Get server time failed');
  }

  // ========== 认证 ==========

  public async register(anonymousUuid: string): Promise<string> {
    const body: RegisterRequest = { anonymousUuid: anonymousUuid };
    const resp: ApiResponse<AuthData> =
      await this.postNoAuth<ApiResponse<AuthData>>('/api/auth/register', body);
    if (resp.data !== null) {
      AuthService.getInstance().setToken(resp.data.token);
      return resp.data.token;
    }
    throw new Error('Register failed');
  }

  public async refreshToken(): Promise<string> {
    const resp: ApiResponse<AuthData> =
      await this.post<ApiResponse<AuthData>>('/api/auth/refresh');
    if (resp.data !== null) {
      AuthService.getInstance().setToken(resp.data.token);
      return resp.data.token;
    }
    throw new Error('Refresh token failed');
  }

  // ========== 声呐 ==========

  public async sendSonar(content: string, geohash: string): Promise<ApiResponse<SonarSendData>> {
    const body: SendSonarRequest = { content: content, geohash: geohash };
    return await this.post<ApiResponse<SonarSendData>>('/api/sonar', body);
  }

  public async getReceivedSonars(): Promise<ReceivedSonarData[]> {
    const resp: ApiResponse<ReceivedSonarData[]> =
      await this.get<ApiResponse<ReceivedSonarData[]>>('/api/sonar/received');
    return resp.data !== null ? resp.data : [];
  }

  public async acceptSonar(sonarId: string): Promise<AcceptSonarData> {
    const resp: ApiResponse<AcceptSonarData> =
      await this.post<ApiResponse<AcceptSonarData>>(`/api/sonar/${sonarId}/accept`);
    if (resp.data !== null) {
      return resp.data;
    }
    throw new Error('Accept sonar failed');
  }

  public async ignoreSonar(sonarId: string): Promise<void> {
    await this.post<ApiResponse<null>>(`/api/sonar/${sonarId}/ignore`);
  }

  public async startListening(geohash: string): Promise<void> {
    await this.post<ApiResponse<null>>(`/api/sonar/listen?geohash=${encodeURIComponent(geohash)}`);
  }

  public async stopListening(geohash: string): Promise<void> {
    await this.post<ApiResponse<null>>(`/api/sonar/unlisten?geohash=${encodeURIComponent(geohash)}`);
  }

  // 附近活跃用户数（雷达 blip 真实化）
  public async getNearbyActivity(geohash: string): Promise<NearbyActivityData | null> {
    const resp: ApiResponse<NearbyActivityData> =
      await this.get<ApiResponse<NearbyActivityData>>(`/api/sonar/nearby-activity?geohash=${encodeURIComponent(geohash)}`);
    return resp.data;
  }

  // ========== 对话房间 ==========

  public async getRooms(): Promise<RoomData[]> {
    const resp: ApiResponse<RoomData[]> =
      await this.get<ApiResponse<RoomData[]>>('/api/rooms');
    return resp.data !== null ? resp.data : [];
  }

  public async getRoom(roomId: string): Promise<RoomData> {
    const resp: ApiResponse<RoomData> =
      await this.get<ApiResponse<RoomData>>(`/api/rooms/${roomId}`);
    if (resp.data !== null) {
      return resp.data;
    }
    throw new Error('Get room failed');
  }

  public async getMessages(roomId: string, offset: number, limit: number): Promise<MessagesData> {
    const resp: ApiResponse<MessagesData> =
      await this.get<ApiResponse<MessagesData>>(`/api/rooms/${roomId}/messages?offset=${offset}&limit=${limit}`);
    if (resp.data !== null) {
      return resp.data;
    }
    throw new Error('Get messages failed');
  }

  public async unlockProfile(roomId: string): Promise<UnlockData> {
    const resp: ApiResponse<UnlockData> =
      await this.post<ApiResponse<UnlockData>>(`/api/rooms/${roomId}/unlock`);
    if (resp.data !== null) {
      return resp.data;
    }
    throw new ApiBusinessError(resp.code, resp.message, '资料尚未可解锁');
  }

  public async saveConnection(roomId: string): Promise<SaveConnectionData> {
    const body: SaveConnectionRequestBody = { agree: true };
    const resp: ApiResponse<SaveConnectionData> =
      await this.post<ApiResponse<SaveConnectionData>>(`/api/rooms/${roomId}/save`, body);
    if (resp.data !== null) {
      return resp.data;
    }
    throw new ApiBusinessError(resp.code, resp.message, '保存连接失败，请稍后再试');
  }

  public async refuseSaveConnection(roomId: string): Promise<SaveConnectionData> {
    const body: SaveConnectionRequestBody = { agree: false };
    const resp: ApiResponse<SaveConnectionData> =
      await this.post<ApiResponse<SaveConnectionData>>(`/api/rooms/${roomId}/save`, body);
    if (resp.data !== null) {
      return resp.data;
    }
    throw new Error('Refuse save connection failed');
  }

  public async leaveRoom(roomId: string): Promise<void> {
    await this.post<ApiResponse<null>>(`/api/rooms/${roomId}/leave`);
  }

  public async blockUser(roomId: string): Promise<void> {
    await this.post<ApiResponse<null>>(`/api/rooms/${roomId}/block`);
  }

  public async getBlockedList(): Promise<string[]> {
    const resp: ApiResponse<string[]> =
      await this.get<ApiResponse<string[]>>('/api/blocks');
    return resp.data !== null ? resp.data : [];
  }

  public async unblockUser(blockedUserId: string): Promise<void> {
    await this.delete<ApiResponse<null>>(`/api/blocks/${blockedUserId}`);
  }

  // 重置匿名身份（清除服务端所有数据）
  public async resetIdentity(): Promise<void> {
    await this.delete<ApiResponse<null>>('/api/profile/reset');
  }

  public async markAsRead(roomId: string, messageId: string): Promise<void> {
    await this.put<ApiResponse<null>>(`/api/rooms/${roomId}/read?messageId=${encodeURIComponent(messageId)}`);
  }

  // ========== 推送 ==========

  public async registerPushToken(pushToken: string): Promise<void> {
    await this.post<ApiResponse<null>>(`/api/push/register?pushToken=${encodeURIComponent(pushToken)}`);
  }

  public async unregisterPushToken(): Promise<void> {
    await this.delete<ApiResponse<null>>('/api/push/token');
  }

  // ========== 用户资料 ==========

  public async getProfile(): Promise<ProfileData> {
    const resp: ApiResponse<ProfileData> =
      await this.get<ApiResponse<ProfileData>>('/api/profile');
    if (resp.data !== null) {
      return resp.data;
    }
    const empty: ProfileData = { signature: '', city: '', contact: '' };
    return empty;
  }

  public async updateProfile(signature: string, city: string, contact: string): Promise<ProfileData> {
    const body: UpdateProfileRequest = { signature: signature, city: city, contact: contact };
    const resp: ApiResponse<ProfileData> =
      await this.put<ApiResponse<ProfileData>>('/api/profile', body);
    if (resp.data !== null) {
      return resp.data;
    }
    throw new Error('Update profile failed');
  }

  // ========== 举报 ==========

  public async reportRoom(roomId: string, reason: string, phoneNumber: string): Promise<string> {
    const body: ReportRequest = { roomId: roomId, reason: reason, phoneNumber: phoneNumber };
    const resp: ApiResponse<ReportData> =
      await this.post<ApiResponse<ReportData>>('/api/report', body);
    if (resp.data !== null) {
      return resp.data.reportId;
    }
    throw new Error('Report failed');
  }

  // ========== 临终保存片段 ==========

  public async saveMoment(roomId: string, content: string): Promise<SavedMomentData> {
    const body: SaveMomentRequest = { roomId: roomId, content: content };
    const resp: ApiResponse<SavedMomentData> =
      await this.post<ApiResponse<SavedMomentData>>('/api/moments', body);
    if (resp.data !== null) {
      return resp.data;
    }
    throw new Error('Save moment failed');
  }

  public async getSavedMoments(): Promise<SavedMomentData[]> {
    const resp: ApiResponse<SavedMomentData[]> =
      await this.get<ApiResponse<SavedMomentData[]>>('/api/moments');
    return resp.data !== null ? resp.data : [];
  }

  // ========== 通用请求方法 ==========

  private get<T>(path: string): Promise<T> {
    return this.request<T>(http.RequestMethod.GET, path, '');
  }

  private post<T>(path: string, data?: Object): Promise<T> {
    const body: string = data !== undefined ? JSON.stringify(data) : '';
    return this.request<T>(http.RequestMethod.POST, path, body);
  }

  private put<T>(path: string, data?: Object): Promise<T> {
    const body: string = data !== undefined ? JSON.stringify(data) : '';
    return this.request<T>(http.RequestMethod.PUT, path, body);
  }

  private delete<T>(path: string): Promise<T> {
    return this.request<T>(http.RequestMethod.DELETE, path, '');
  }

  private postNoAuth<T>(path: string, data?: Object): Promise<T> {
    const body: string = data !== undefined ? JSON.stringify(data) : '';
    return this.requestNoAuth<T>(http.RequestMethod.POST, path, body);
  }

  private requestNoAuth<T>(method: http.RequestMethod, path: string, body: string): Promise<T> {
    return new Promise<T>((resolve, reject) => {
      const httpRequest: http.HttpRequest = http.createHttp();
      const url: string = Constants.API_BASE_URL + path;

      const header: Record<string, string> = {
        'Content-Type': 'application/json'
      };

      const options: http.HttpRequestOptions = {
        method: method,
        header: header,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 60000,
        readTimeout: 60000
      };
      if (body.length > 0) {
        options.extraData = body;
      }

      httpRequest.request(url, options, (err: BusinessError, response: http.HttpResponse) => {
        httpRequest.destroy();
        if (err) {
          Logger.error(`[ApiService] Request error: ${err.message}`);
          const errResp: ApiResponse<Object> = { code: -1, data: null, message: err.message };
          resolve(errResp as T);
          return;
        }
        if (response.responseCode === 200 || response.responseCode === 201) {
          try {
            const result: T = JSON.parse(response.result as string) as T;
            resolve(result);
          } catch (parseErr) {
            const parseResp: ApiResponse<Object> = { code: -1, data: null, message: '解析响应失败' };
            resolve(parseResp as T);
          }
        } else {
          try {
            const errBody: Record<string, Object> = JSON.parse(response.result as string) as Record<string, Object>;
            const errCode: number = (errBody['code'] as number) || -1;
            const errMessage: string = (errBody['message'] as string) || `HTTP ${response.responseCode}`;
            const errResp: ApiResponse<Object> = { code: errCode, data: null, message: errMessage };
            resolve(errResp as T);
          } catch (e) {
            const errResp: ApiResponse<Object> = { code: -1, data: null, message: `HTTP ${response.responseCode}` };
            resolve(errResp as T);
          }
        }
      });
    });
  }

  private request<T>(method: http.RequestMethod, path: string, body: string): Promise<T> {
    return this._requestWithRetry<T>(method, path, body, false);
  }

  private _requestWithRetry<T>(method: http.RequestMethod, path: string, body: string,
    isRetry: boolean): Promise<T> {
    return new Promise<T>((resolve, reject) => {
      const httpRequest: http.HttpRequest = http.createHttp();
      const url: string = Constants.API_BASE_URL + path;
      const token: string = AuthService.getInstance().getToken();

      const header: Record<string, string> = {
        'Content-Type': 'application/json'
      };
      if (token.length > 0) {
        header['Authorization'] = `Bearer ${token}`;
      }

      const options: http.HttpRequestOptions = {
        method: method,
        header: header,
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 60000,
        readTimeout: 60000
      };
      if (body.length > 0) {
        options.extraData = body;
      }

      httpRequest.request(url, options, (err: BusinessError, response: http.HttpResponse) => {
        httpRequest.destroy();
        if (err) {
          Logger.error(`[ApiService] Request error: ${err.message}`);
          const errResp: ApiResponse<Object> = { code: -1, data: null, message: err.message };
          resolve(errResp as T);
          return;
        }
        if (response.responseCode === 200 || response.responseCode === 201) {
          try {
            const result: T = JSON.parse(response.result as string) as T;
            resolve(result);
          } catch (parseErr) {
            const parseResp: ApiResponse<Object> = { code: -1, data: null, message: '解析响应失败' };
            resolve(parseResp as T);
          }
        } else if (response.responseCode === 401 && !isRetry) {
          const uuid: string = AuthService.getInstance().getUuid();
          this.refreshToken().then(() => {
            this._requestWithRetry<T>(method, path, body, true).then(resolve).catch(() => {
              const r: ApiResponse<Object> = { code: 40101, data: null, message: '登录已过期' };
              resolve(r as T);
            });
          }).catch(() => {
            if (uuid.length > 0) {
              this.register(uuid).then(() => {
                this._requestWithRetry<T>(method, path, body, true).then(resolve).catch(() => {
                  const r: ApiResponse<Object> = { code: 40101, data: null, message: '登录已过期' };
                  resolve(r as T);
                });
              }).catch(() => {
                const r: ApiResponse<Object> = { code: 40101, data: null, message: '登录已过期' };
                resolve(r as T);
              });
            } else {
              const r: ApiResponse<Object> = { code: 40101, data: null, message: '登录已过期' };
              resolve(r as T);
            }
          });
        } else {
          try {
            const errBody: Record<string, Object> = JSON.parse(response.result as string) as Record<string, Object>;
            const errCode: number = (errBody['code'] as number) || -1;
            const errMessage: string = (errBody['message'] as string) || `HTTP ${response.responseCode}`;
            const errResp: ApiResponse<Object> = { code: errCode, data: null, message: errMessage };
            resolve(errResp as T);
          } catch (e) {
            const errResp: ApiResponse<Object> = { code: -1, data: null, message: `HTTP ${response.responseCode}` };
            resolve(errResp as T);
          }
        }
      });
    });
  }
}
