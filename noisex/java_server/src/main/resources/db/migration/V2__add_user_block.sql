-- NoiseX V2: 用户屏蔽表
-- 用户可以屏蔽骚扰者，屏蔽后不再收到对方的声呐和匹配

CREATE TABLE user_block (
    blocker_id  VARCHAR(36)  NOT NULL COMMENT '屏蔽者UUID',
    blocked_id  VARCHAR(36)  NOT NULL COMMENT '被屏蔽者UUID',
    created_at  BIGINT       NOT NULL COMMENT '屏蔽时间戳',

    PRIMARY KEY (blocker_id, blocked_id),
    INDEX idx_blocker (blocker_id),
    INDEX idx_blocked (blocked_id),
    INDEX idx_created (created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='用户屏蔽关系';
