fx_version 'cerulean'
game 'gta5'
author 'AEOM Development'
lua54 'yes'

name 'SPIN ARENA'
description '[Édition gratuite] Combats de toupies mécaniques : duels autoritaires, assemblages, boutique, arènes et classement persistant.'
version '0.6.0'

-- framework (ESX / QBCore / Qbox), inventaire (ox complet ; qs / qb par menus) et ciblage (ox_target / qb-target)
-- détectés par bridge/
dependencies {
    'ox_lib',
}

ui_page 'web/index.html'

files {
    'sql/install.sql',
    'web/index.html',
    'web/style.css',
    'web/app.js',
    'web/combat_audio.js',
    'web/window_layout.js',
    'web/launch_gauge.js',
    'web/match_summary.js',
    'web/img/manifest.js',
    -- Un dossier par motif : FiveM ne résout pas « web/img/*/*.webp » (avertissement « could not find file »)
    'web/img/tops/*.webp',
    'web/img/launchers/*.webp',
    'web/img/parts/*.webp',
    -- web/img/repair : à ajouter avec son premier rendu (un motif sans fichier = avertissement)
}

-- Modèles 3D originaux (stream/*.ydr), déclarés par le .ytyp
data_file 'DLC_ITYP_REQUEST' 'stream/spin_arena.ytyp'
data_file 'DLC_ITYP_REQUEST' 'stream/spin_arena_tables_pedestal.ytyp'
-- 29/10 : une pièce de toupie = un modèle (Lame, Verrou, Embout, Noyau), assemblés par le client (tools/models/build_parts.py)
data_file 'DLC_ITYP_REQUEST' 'stream/spin_arena_parts.ytyp'

shared_scripts {
    '@ox_lib/init.lua',
    'config/shared.lua',
    'config/parts.lua',
    'shared/protocol.lua',
    'shared/stats.lua',
    'shared/launch.lua',
}

-- Configuration serveur, moteur et modules : jamais téléchargés par les clients
server_scripts {
    'config/server.lua',
    'shared/rng.lua',
    'server/physics/collisions.lua',
    'server/physics/boundaries.lua',
    'server/physics/engine.lua',
    'server/runner.lua',
    'bridge/server.lua',
    'server/bridge.lua',
    'server/database.lua',
    'server/inventory.lua',
    'server/security.lua',
    'server/arenas.lua',
    'server/matches.lua',
    'server/challenges.lua',
    'server/queue.lua',
    'server/ranking.lua',
    'server/ranking_sql.lua',
    'server/parts.lua',
    'server/shop.lua',
    'server/pro_stub.lua',
    'server/admin_panel.lua',
    'server/selfcheck.lua',
    'server/main.lua',
    'server/debug.lua',
}

client_scripts {
    'bridge/client.lua',
    'client/target_compat.lua',
    'locales/fr.lua',
    'locales/en.lua',
    'client/effects.lua',
    'client/top_model.lua',
    'client/launcher.lua',
    'client/launcher_rivals.lua',
    'client/spectacle.lua',
    'client/renderer.lua',
    'client/main.lua',
    'client/concierge.lua',
    'client/shop_vendor.lua',
    'client/nui.lua',
    'client/launch.lua',
    'client/hologram.lua',
    'client/admin_panel.lua',
    'client/summary.lua',
}
