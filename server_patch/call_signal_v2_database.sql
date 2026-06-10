-- Blinlin Call Signal v2 database hardening
-- 用途：让后端通话信令表支持结构化 JSON、严格去重和高效补偿拉取。
-- 注意：执行前请先备份数据库。以下 SQL 尽量使用 MySQL 8 / MariaDB 兼容写法。

-- 1. 如果原表不存在，可用此建表语句。
-- 如果已存在 mr_im_call_signals，请不要直接 DROP，改用后面的 ALTER。
CREATE TABLE IF NOT EXISTS `mr_im_call_signals` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `call_id` VARCHAR(96) NOT NULL COMMENT '一次通话唯一ID',
  `signal_id` VARCHAR(128) NOT NULL COMMENT '单条信令唯一ID',
  `schema_name` VARCHAR(64) NOT NULL DEFAULT 'blinlin.call.signal.v2',
  `msg_type` VARCHAR(32) NOT NULL DEFAULT 'call_signal',
  `action` VARCHAR(24) NOT NULL COMMENT 'invite/offer/accept/answer/ice/hangup/reject/cancel/timeout/ack',
  `media` VARCHAR(16) NOT NULL DEFAULT 'audio' COMMENT 'audio/video',
  `from_user_id` BIGINT UNSIGNED NOT NULL,
  `to_user_id` BIGINT UNSIGNED NOT NULL,
  `from_uid` VARCHAR(96) NOT NULL DEFAULT '',
  `to_uid` VARCHAR(96) NOT NULL DEFAULT '',
  `device_id` VARCHAR(128) NOT NULL DEFAULT '',
  `seq` INT UNSIGNED NOT NULL DEFAULT 0,
  `payload_json` JSON NULL COMMENT '结构化信令完整JSON',
  `dedupe_key` VARCHAR(160) NOT NULL DEFAULT '',
  `state_before` VARCHAR(32) NOT NULL DEFAULT '',
  `state_after` VARCHAR(32) NOT NULL DEFAULT '',
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_call_signal_id` (`signal_id`),
  KEY `idx_call_id` (`call_id`),
  KEY `idx_to_user_id_id` (`to_user_id`, `id`),
  KEY `idx_from_user_id_id` (`from_user_id`, `id`),
  KEY `idx_call_action` (`call_id`, `action`),
  KEY `idx_created_at` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='Blinlin结构化通话信令表';

-- 2. 如果原表已存在，按需补字段。
-- MySQL 8.0.29+ 支持 ADD COLUMN IF NOT EXISTS；老版本不支持时，请逐条检查字段后执行。
ALTER TABLE `mr_im_call_signals`
  ADD COLUMN IF NOT EXISTS `signal_id` VARCHAR(128) NOT NULL DEFAULT '' COMMENT '单条信令唯一ID',
  ADD COLUMN IF NOT EXISTS `schema_name` VARCHAR(64) NOT NULL DEFAULT 'blinlin.call.signal.v2',
  ADD COLUMN IF NOT EXISTS `msg_type` VARCHAR(32) NOT NULL DEFAULT 'call_signal',
  ADD COLUMN IF NOT EXISTS `action` VARCHAR(24) NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS `media` VARCHAR(16) NOT NULL DEFAULT 'audio',
  ADD COLUMN IF NOT EXISTS `from_uid` VARCHAR(96) NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS `to_uid` VARCHAR(96) NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS `device_id` VARCHAR(128) NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS `seq` INT UNSIGNED NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS `payload_json` JSON NULL,
  ADD COLUMN IF NOT EXISTS `dedupe_key` VARCHAR(160) NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS `state_before` VARCHAR(32) NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS `state_after` VARCHAR(32) NOT NULL DEFAULT '';

-- 3. 旧 MySQL/MariaDB 如果不支持 JSON 类型，可把 payload_json 改为 LONGTEXT：
-- ALTER TABLE `mr_im_call_signals` ADD COLUMN `payload_json` LONGTEXT NULL;

-- 4. 索引/唯一约束。老版本不支持 IF NOT EXISTS 时，先 SHOW INDEX FROM mr_im_call_signals; 再执行。
CREATE UNIQUE INDEX IF NOT EXISTS `uk_call_signal_id` ON `mr_im_call_signals` (`signal_id`);
CREATE INDEX IF NOT EXISTS `idx_call_id` ON `mr_im_call_signals` (`call_id`);
CREATE INDEX IF NOT EXISTS `idx_to_user_id_id` ON `mr_im_call_signals` (`to_user_id`, `id`);
CREATE INDEX IF NOT EXISTS `idx_from_user_id_id` ON `mr_im_call_signals` (`from_user_id`, `id`);
CREATE INDEX IF NOT EXISTS `idx_call_action` ON `mr_im_call_signals` (`call_id`, `action`);

-- 5. 若旧数据 signal_id 为空，先用 id 补临时 signal_id，避免唯一索引失败。
-- UPDATE `mr_im_call_signals`
-- SET `signal_id` = CONCAT(COALESCE(NULLIF(`call_id`, ''), 'legacy_call'), '_legacy_', `id`)
-- WHERE `signal_id` = '' OR `signal_id` IS NULL;

-- 6. 后端必须保证 action 白名单：
-- invite, offer, accept, answer, ice, hangup, reject, cancel, timeout, ack
-- 如果数据库支持 CHECK，可加：
-- ALTER TABLE `mr_im_call_signals`
-- ADD CONSTRAINT `chk_call_action_v2`
-- CHECK (`action` IN ('invite','offer','accept','answer','ice','hangup','reject','cancel','timeout','ack'));
