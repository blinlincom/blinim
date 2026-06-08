-- Blinlin IM friend relationship patch
-- Run once before deploying the PHP endpoints.

CREATE TABLE IF NOT EXISTS `im_friends` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `user_id` BIGINT UNSIGNED NOT NULL,
  `friend_id` BIGINT UNSIGNED NOT NULL,
  `status` TINYINT NOT NULL DEFAULT 1 COMMENT '1=friend,0=deleted',
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uniq_friend_pair` (`user_id`, `friend_id`),
  KEY `idx_friend_id` (`friend_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `im_friend_requests` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `from_user_id` BIGINT UNSIGNED NOT NULL,
  `to_user_id` BIGINT UNSIGNED NOT NULL,
  `message` VARCHAR(255) NOT NULL DEFAULT '',
  `status` TINYINT NOT NULL DEFAULT 0 COMMENT '0=pending,1=accepted,2=rejected',
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uniq_friend_request` (`from_user_id`, `to_user_id`),
  KEY `idx_to_user_status` (`to_user_id`, `status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

ALTER TABLE `messages`
  ADD COLUMN `im_payload` MEDIUMTEXT NULL,
  ADD COLUMN `file_path` VARCHAR(500) NOT NULL DEFAULT '',
  ADD COLUMN `file_name` VARCHAR(255) NOT NULL DEFAULT '';
