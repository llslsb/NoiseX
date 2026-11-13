package com.noisex.util;

/** Redis Key 常量统一管理 命名规范: noisex:{module}:{identifier}[:sub] */
public final class RedisKeys {

    private RedisKeys() {}

    // 声呐
    public static final String SONAR_QUEUE_PREFIX = "noisex:sonar:queue:";
    public static final String SONAR_RECEIVED_PREFIX = "noisex:sonar:received:";
    public static final String RATE_LIMIT_PREFIX = "noisex:rate:sonar:";
    public static final String SONAR_DUPLICATE_PREFIX =
            "noisex:sonar:duplicate:"; // 声呐内容重复检测 (userId, TTL 由
    // noisex.sonar.duplicate-window-seconds 配置)

    // 收听者
    public static final String LISTENER_PREFIX = "noisex:listener:";

    // 房间创建时间索引 (ZSET: score=createdAt timestamp, member=roomId)
    public static final String ROOM_CREATED_AT_ZSET = "noisex:room:created_at";

    // 用户收听 geohash 索引 (Set: 记录用户注册为收听者的 geohash 列表)
    public static final String USER_LISTENING_GEOHASHES_PREFIX = "noisex:user:listening_geohashes:";

    // 房间
    public static final String ROOM_PREFIX = "noisex:room:";
    public static final String ROOM_MESSAGES_PREFIX = "noisex:room:messages:";
    public static final String ROOM_DEEP_PREFIX = "noisex:room:deep:";
    public static final String ROOM_SAVE_PREFIX = "noisex:room:save:";
    public static final String ROOM_USERS_PREFIX = "noisex:room:users:";

    // 用户
    public static final String USER_ROOMS_PREFIX = "noisex:user:rooms:";

    // 用户封禁标记 (管理员封禁后写入, TTL 与 JWT 黑名单一致为 7 天, 到期自动解封)
    public static final String USER_BANNED_PREFIX = "noisex:user:banned:";

    // 匿名 UUID -> 最近签发 JWT 的缓存 (AuthService 登录用, TTL 30 天)
    public static final String AUTH_UUID_CACHE_PREFIX = "noisex:auth:uuid:";

    // 在线
    public static final String ONLINE = "noisex:online";

    // 已读指针
    public static final String ROOM_READ_PREFIX = "noisex:room:read:";

    // 屏蔽
    public static final String BLOCK_PREFIX = "noisex:block:";

    // 推送 Token
    public static final String PUSH_TOKEN_PREFIX = "noisex:push:token:";

    // JWT 黑名单
    public static final String JWT_BLACKLIST = "noisex:jwt:blacklist";

    // 管理员登录限流 (ip:usernameHash, TTL 由 noisex.admin.login.window-seconds 配置)
    public static final String ADMIN_LOGIN_RATE_PREFIX = "noisex:rate:admin_login:";

    // 消息反作弊
    public static final String MSG_RATE_PREFIX =
            "noisex:rate:msg:"; // 消息频率限制 (userId, TTL 由 noisex.chat.msg-rate-seconds 配置)
    public static final String MSG_LAST_PREFIX =
            "noisex:msg:last:"; // 上一条消息内容 (roomId:userId, TTL 由
    // noisex.chat.duplicate-window-seconds 配置)
}
