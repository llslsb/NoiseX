-- NoiseX V4: 补偿重试表
-- 跨存储（MySQL + Redis）操作失败时记录补偿任务，由定时任务重试

CREATE TABLE pending_compensation (
    id              VARCHAR(32)   PRIMARY KEY COMMENT '补偿任务ID',
    operation       VARCHAR(64)   NOT NULL COMMENT '操作类型',
    payload         TEXT          NOT NULL COMMENT '操作参数(JSON)',
    status          ENUM('PENDING', 'RETRYING', 'DONE', 'FAILED')
                    NOT NULL DEFAULT 'PENDING' COMMENT '状态',
    retry_count     INT           NOT NULL DEFAULT 0 COMMENT '已重试次数',
    max_retries     INT           NOT NULL DEFAULT 3 COMMENT '最大重试次数',
    created_at      BIGINT        NOT NULL COMMENT '创建时间戳',
    next_retry_at   BIGINT        NOT NULL COMMENT '下次重试时间戳',

    INDEX idx_status (status),
    INDEX idx_next_retry (next_retry_at),
    INDEX idx_created (created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
  COMMENT='跨存储补偿重试任务';
