-- 保存连接按房间实例隔离：同一对用户的不同连接可以分别保存。
ALTER TABLE saved_connection
    ADD COLUMN room_id VARCHAR(32) NULL COMMENT '来源房间ID' AFTER user_id_b;

UPDATE saved_connection
SET room_id = id
WHERE room_id IS NULL;

ALTER TABLE saved_connection
    MODIFY room_id VARCHAR(32) NOT NULL COMMENT '来源房间ID',
    ADD UNIQUE INDEX uk_saved_connection_room (room_id),
    ADD INDEX idx_saved_connection_users (user_id_a, user_id_b);
