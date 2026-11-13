-- NoiseX V5: 管理员账号凭据表
-- 管理后台使用独立账号密码登录，密码仅保存 BCrypt 哈希。

CREATE TABLE admin_account (
    id VARCHAR(32) PRIMARY KEY COMMENT '管理员账号ID',
    username VARCHAR(64) NOT NULL COMMENT '管理员登录名',
    user_id VARCHAR(36) NOT NULL COMMENT '关联user_profile.user_id',
    password_hash VARCHAR(100) NOT NULL COMMENT 'BCrypt密码哈希',
    enabled BOOLEAN NOT NULL DEFAULT TRUE COMMENT '是否启用',
    created_at BIGINT NOT NULL COMMENT '创建时间戳',
    updated_at BIGINT NOT NULL COMMENT '更新时间戳',
    last_login_at BIGINT NULL COMMENT '最后登录时间戳',

    UNIQUE KEY uk_admin_username (username),
    UNIQUE KEY uk_admin_user_id (user_id),
    INDEX idx_admin_enabled (enabled)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='管理员账号凭据';
