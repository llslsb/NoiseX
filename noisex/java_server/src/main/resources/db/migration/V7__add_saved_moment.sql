-- NoiseX V7: 临终保存片段表
-- 用户在房间即将过期时保存的最后消息片段

CREATE TABLE saved_moment (
    id          VARCHAR(32)  PRIMARY KEY COMMENT '片段ID',
    room_id     VARCHAR(32)  NOT NULL COMMENT '房间ID',
    user_id     VARCHAR(36)  NOT NULL COMMENT '用户UUID',
    content     VARCHAR(500) NOT NULL COMMENT '保存的片段内容',
    created_at  BIGINT       NOT NULL COMMENT '保存时间戳',

    INDEX idx_room (room_id),
    INDEX idx_user (user_id),
    INDEX idx_created (created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='临终保存片段';
