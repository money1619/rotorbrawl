-- SPIN ARENA — schéma (phase 4). Rejouable : chaque instruction est idempotente.
-- Le serveur exécute aussi ces instructions au démarrage si oxmysql est disponible (server/database.lua).

CREATE TABLE IF NOT EXISTS `spin_tops` (
    `uid` VARCHAR(24) NOT NULL,
    `owner` VARCHAR(64) NULL,
    `name` VARCHAR(24) NOT NULL DEFAULT 'Toupie',
    `parts` VARCHAR(255) NOT NULL,
    `paint` VARCHAR(16) NOT NULL DEFAULT 'titanium',
    `wear` INT NOT NULL DEFAULT 0,
    `wins` INT NOT NULL DEFAULT 0,
    `losses` INT NOT NULL DEFAULT 0,
    `draws` INT NOT NULL DEFAULT 0,
    `locked_match` VARCHAR(48) NULL,
    `version` INT NOT NULL DEFAULT 1,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`uid`),
    KEY `idx_spin_tops_owner` (`owner`),
    KEY `idx_spin_tops_locked` (`locked_match`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Atomic ranking deduplication marker, committed with both rating rows.
CREATE TABLE IF NOT EXISTS `spin_rating_matches` (
    `match_id` VARCHAR(64) NOT NULL,
    `season` INT NOT NULL,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`match_id`, `season`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Journal des opérations qui touchent à la fois l'inventaire et la base (docs/SECURITY.md §8)
CREATE TABLE IF NOT EXISTS `spin_ops` (
    `id` BIGINT NOT NULL AUTO_INCREMENT,
    `identifier` VARCHAR(64) NOT NULL,
    `uid` VARCHAR(24) NOT NULL,
    `op` VARCHAR(16) NOT NULL,
    `payload` VARCHAR(255) NULL,
    `status` VARCHAR(16) NOT NULL,
    `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    KEY `idx_spin_ops_status` (`status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Classement (phase 6, server/ranking.lua)
CREATE TABLE IF NOT EXISTS `spin_ratings` (
    `identifier` VARCHAR(64) NOT NULL,
    `season` INT NOT NULL,
    `name` VARCHAR(64) NOT NULL DEFAULT '',
    `rating` INT NOT NULL,
    `wins` INT NOT NULL DEFAULT 0,
    `losses` INT NOT NULL DEFAULT 0,
    `draws` INT NOT NULL DEFAULT 0,
    `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`identifier`, `season`),
    KEY `idx_spin_ratings_board` (`season`, `rating`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
