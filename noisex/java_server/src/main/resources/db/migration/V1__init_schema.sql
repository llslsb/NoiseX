-- NoiseX V1: 初始数据库结构
-- MySQL 仅存储需要永久保留的数据

-- 用户资料卡表（用户自行设置，仅解锁后可见）
CREATE TABLE user_profile (
    user_id     VARCHAR(36)  PRIMARY KEY COMMENT '匿名UUID',
    signature   VARCHAR(200) NULL     COMMENT '一句签名',
    city        VARCHAR(50)  NULL     COMMENT '城市',
    contact     VARCHAR(200) NULL     COMMENT '公开联系方式',
    updated_at  BIGINT       NOT NULL COMMENT '更新时间戳',

    INDEX idx_updated (updated_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='用户资料卡（仅解锁后可见）';

-- 已保存连接表（永久存储）
CREATE TABLE saved_connection (
    id          VARCHAR(32)  PRIMARY KEY COMMENT '连接ID',
    user_id_a   VARCHAR(36)  NOT NULL COMMENT '用户A的UUID',
    user_id_b   VARCHAR(36)  NOT NULL COMMENT '用户B的UUID',
    created_at  BIGINT       NOT NULL COMMENT '保存时间戳',

    INDEX idx_user_a (user_id_a),
    INDEX idx_user_b (user_id_b),
    INDEX idx_created (created_at),

    CONSTRAINT chk_user_order CHECK (user_id_a < user_id_b)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='已保存连接（双方同意后长期保留）';

-- 举报记录表（唯一举报途径）
CREATE TABLE report (
    id            VARCHAR(32)  PRIMARY KEY COMMENT '举报ID',
    reporter_id   VARCHAR(36)  NOT NULL COMMENT '举报人UUID',
    room_id       VARCHAR(32)  NOT NULL COMMENT '房间ID',
    reason        VARCHAR(500) NOT NULL COMMENT '举报原因',
    phone_number  VARCHAR(20)  NULL     COMMENT '手机号（临时收集用于法律追溯）',
    status        ENUM('pending', 'reviewed', 'dismissed', 'banned')
                               NOT NULL DEFAULT 'pending' COMMENT '处理状态',
    created_at    BIGINT       NOT NULL COMMENT '举报时间戳',
    reviewed_at   BIGINT       NULL     COMMENT '审核时间戳',

    INDEX idx_status (status),
    INDEX idx_created (created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='举报记录';
