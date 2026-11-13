-- NoiseX V6: 扩展 report.phone_number 列长度
-- 手机号经 AES-256-GCM 加密后 Base64 编码约 52-100 字符，原 VARCHAR(20) 不足。
-- 同步放宽 DTO 长度校验。

ALTER TABLE report MODIFY COLUMN phone_number VARCHAR(200) NULL COMMENT '加密手机号（AES-256-GCM Base64）';
