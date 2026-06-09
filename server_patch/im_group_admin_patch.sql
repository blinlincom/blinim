-- 群管理增强字段迁移
-- 适用于 ThinkPHP 表前缀 mr_ 的当前线上库；执行前请先备份数据库。

ALTER TABLE `mr_im_groups`
  ADD COLUMN `avatar` VARCHAR(500) NOT NULL DEFAULT '' AFTER `name`,
  ADD COLUMN `notice` VARCHAR(1000) NOT NULL DEFAULT '' AFTER `avatar`,
  ADD COLUMN `owner_id` INT(11) NOT NULL DEFAULT 0 AFTER `notice`,
  ADD COLUMN `mute_all` TINYINT(1) NOT NULL DEFAULT 0 AFTER `member_count`,
  ADD COLUMN `status` TINYINT(1) NOT NULL DEFAULT 1 AFTER `mute_all`,
  ADD COLUMN `update_time` DATETIME NULL AFTER `create_time`;

ALTER TABLE `mr_im_group_members`
  ADD COLUMN `role` TINYINT(1) NOT NULL DEFAULT 0 COMMENT '0成员 1管理员 2群主' AFTER `user_id`,
  ADD COLUMN `nickname` VARCHAR(100) NOT NULL DEFAULT '' AFTER `role`,
  ADD COLUMN `mute_until` DATETIME NULL AFTER `nickname`,
  ADD COLUMN `status` TINYINT(1) NOT NULL DEFAULT 1 AFTER `mute_until`,
  ADD COLUMN `update_time` DATETIME NULL AFTER `create_time`;

ALTER TABLE `mr_im_group_messages`
  ADD COLUMN `payload` MEDIUMTEXT NULL AFTER `content`,
  ADD COLUMN `client_msg_no` VARCHAR(128) NOT NULL DEFAULT '' AFTER `payload`;

CREATE INDEX `idx_im_groups_owner` ON `mr_im_groups` (`owner_id`);
CREATE INDEX `idx_im_group_members_role` ON `mr_im_group_members` (`group_id`, `role`);
CREATE INDEX `idx_im_group_members_status` ON `mr_im_group_members` (`group_id`, `status`);
CREATE INDEX `idx_im_group_messages_client` ON `mr_im_group_messages` (`client_msg_no`);

-- 如果线上已经有 owner_id/role/avatar/status 等字段，以上 ALTER 会提示 Duplicate column，属于已存在字段；可忽略或按需逐条执行。