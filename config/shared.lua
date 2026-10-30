-- SPIN ARENA — configuration partagée (phase 1 : prototype physique)
-- Valeurs de départ de docs/PHYSICS.md §13, à calibrer. Aucune valeur de ce fichier
-- n'est relue depuis un client : le serveur utilise sa propre copie.
SpinArena = SpinArena or {}

SpinArena.Config = {
    concierge = { x = 215.76, y = -810.12, z = 30.73, heading = 160.0, model = "s_m_m_autoshop_01" },

    combatAudio = { enabled = true, volume = 0.35 }, -- sons originaux synthétisés localement, volume 0..1

    -- Spectacle du combat (client/spectacle.lua) : affichage seulement, calculé sur les positions reçues du serveur,
    -- sans effet sur le résultat. Chaque bloc se coupe avec enabled = false. Valeurs de départ, à régler en jeu.
    spectacle = {
        trails = { enabled = true, ms = 320, stepMs = 16, glowRange = 0.30, glowIntensity = 1.6 }, -- traînée + lueur
        impactLight = { enabled = true, range = 0.9, intensity = 7.0 }, -- éclair qui éclaire la cuvette à chaque choc
        pockets = { enabled = true, flashMs = 1600 },                   -- poches de sortie éclairées pendant le match
        eject = { enabled = true, speed = 1.0, up = 0.5 },              -- éjectée : vole hors de la table, reste au sol
        fallOver = { enabled = true, deg = 68, ms = 450 },              -- arrêtée : bascule sur le côté
        lean = { enabled = true, maxDeg = 14 },                         -- penche vers l'intérieur des virages
        replay = { enabled = true, windowS = 1.2, speed = 0.4, delayMs = 500 }, -- ralenti du coup final
    },

    -- Panneau lumineux au-dessus de chaque table (client/hologram.lua) : état du match lu dans les scènes du rendu
    -- (préparation, 3-2-1/GO au départ serveur, score, gagnant). Texte ancré dans le monde, aucune page web.
    hologram = {
        enabled = true,
        height = 0.85,         -- au-dessus du haut de la cuvette (m) ; 1,6 m sortait par le haut de l'écran (capture du 19/10)
        maxDistance = 25.0,    -- rien au-delà (portée d'audience)
        fadeFrom = 15.0,       -- s'estompe entre fadeFrom et maxDistance
        scale = 0.34,          -- taille du texte à 10 m
        topMargin = 0.16,      -- rien n'est dessiné si le panneau tombe dans cette bande en haut de l'écran (HUD)
        maxPanels = 4,         -- panneaux dessinés au plus (les plus proches)
    },

    -- Pas de simulation fixe (comparer 1/120 et 1/60 au banc d'essai)
    dt = 1 / 120,

    -- Une keyframe tous les N pas (6 pas à 120 Hz = 20 Hz), plus une à chaque événement
    keyframeEvery = 6,

    physics = {
        g = 9.81,
        beta = 0.01,            -- frottement de l'air (s^-1)
        kWob = 2.0,             -- effet de l'oscillation sur la perte de rotation
        kWobUp = 0.8,           -- montée de l'oscillation sous le seuil (s^-1)
        kWobDown = 0.5,         -- retour au calme au-dessus du seuil (s^-1)
        wWobBase = 140,         -- seuil d'oscillation pour stab = 0 (rad/s)
        wWobStab = 80,          -- baisse du seuil quand stab = 1 (rad/s)
        wStop = 40,             -- sous cette rotation, la toupie s'arrête (rad/s)
        wRef = 250,             -- rotation de référence de l'entraînement (rad/s)
        kDrive = 1.0,           -- multiplicateur de l'entraînement par la pointe (0 = coupé)
        driveFade = 0.08,       -- atténuation de l'entraînement près du centre (m)
        sigma = 0.2,            -- perturbation aléatoire (m/s^2) ; 0,05 avant le 28/10 (trajectoires trop régulières).
                                -- Au-delà de 0,2, le lancer seul inverse balance/défense (tests/launch_unit_test.lua)
        stabNoise = 0.5,        -- la stabilité réduit la perturbation : ×1,5 à stab 0, ×0,5 à stab 1
        vMax = 3.0,             -- vitesse horizontale maximale (m/s)
        eBase = 0.35,           -- restitution de base entre toupies
        eAtk = 0.3,             -- restitution ajoutée par l'attaque moyenne
        eMin = 0.2,
        eMax = 0.8,
        kSmash = 0.15,          -- impulsion due aux bords tournants
        sigmaCap = 30,          -- plafond de la vitesse de glissement (m/s)
        muC = 0.25,             -- frottement au contact entre toupies
        kW = 1.5,               -- part du glissement convertie en perte de rotation
        kImpWob = 0.05,         -- oscillation ajoutée par un choc
        contactCooldown = 0.1,  -- délai avant une nouvelle impulsion de choc (s)
        eWall = 0.55,           -- restitution sur la paroi
        muWall = 0.2,           -- frottement contre la paroi
        vPocket = 0.10,         -- vitesse sortante suffisante dans une poche (m/s)
        vOver = 1.6,            -- vitesse sortante pour passer par-dessus la paroi (m/s)
        startRadius = 0.6,      -- rayon de départ, en fraction de R
        startRadiusJitter = 0.25, -- aléa sur le rayon de départ, par toupie (fraction)
        startSpread = 35,       -- aléa sur la position de départ, par toupie (degrés autour du point opposé)
        launchAngle = 20,       -- part de la vitesse de lancement dirigée vers le centre (degrés)
        launchJitter = 15,      -- aléa sur la direction de lancement (degrés)
        tiltAngle = 45,         -- inclinaison du lanceur : ±45° sur la direction de lancement (+ vers le centre, − vers le bord)
        w0Jitter = 0.05,        -- aléa sur la rotation de lancement (fraction)
        flowerLean = 4.0,       -- inclinaison max de l'entraînement vers le centre (tangente de l'angle)
        flowerFreq = 0.8,       -- pulsation du motif en fleur (rad/s)
        flowerJitter = 0.35,    -- rythme du motif propre à chaque toupie (±fraction) : plongées désynchronisées
        flowerThreshold = 0.5,  -- part du cycle sans plongée (0 = plonge la moitié du temps)
        kSeek = 2.0,            -- recherche de l'adversaire, pondérée par (attaque − défense/2) ; 0 = coupée
        -- Éclatement (29/10) : chaque choc entame le verrou de la toupie frappée ; à zéro, elle éclate (finition ÉCLAT).
        -- Réserve = burstLock × (0,3 + 1,4 × résistance du verrou). Banc du 29/10 : ~15 % des manches finissent ainsi.
        burstLock = 12.5,
        burstSame = 1.3,        -- même sens de rotation : chocs frontaux, plus destructeurs
        burstSpin = 0.8,        -- une toupie qui ralentit tient moins bien son verrou
        -- Rail turbo (29/10) : bande extérieure de la cuvette où l'embout accroche (dash) et accélère.
        -- Une éjection juste après un choc d'une toupie lancée sur le rail = finition TURBO.
        railInner = 0.70,       -- début de la bande (fraction du rayon)
        railBoost = 0.0,        -- rail des tables sans rail : coupé ; la variante « turbo » porte le sien (arenaVariants)
        railTime = 0.45,        -- durée d'une accélération (s)
        railCool = 1.2,         -- attente avant de raccrocher le rail (s)
        railSpinCost = 0.15,    -- rotation dépensée pendant l'accélération (fraction par seconde)
        railExit = 0.35,        -- sortie du rail : relancée vers l'adversaire, +35 % de vitesse
        turboWindow = 1.6,      -- délai entre le choc et l'éjection pour une finition TURBO (s)
    },

    rules = {
        Tmax = 60,              -- durée maximale d'une manche (s)
        stopConfirm = 0.75,     -- durée de confirmation d'un arrêt (s)
        tieEps = 0.02,          -- écart relatif de rotation sous lequel il y a égalité au temps
    },

    -- Arène de test du prototype : cuvette de 1,2 m de diamètre, trois poches de 24°
    testArena = {
        R = 0.60,
        h = 0.08,
        -- Table sur pied « Bastion » (Fermi) ; retour arrière : model = 'spin_arena_bowl', floorHeight = 0.75, rOuter = 0.70
        model = 'spin_arena_table_bastion', -- objet 3D (stream/), origine au sol sous le centre
        floorHeight = 0.800,         -- hauteur du fond de la cuvette au-dessus de l'origine du modèle (m)
        rOuter = 0.792,              -- rayon hors tout du modèle (écarts entre tables ; refonte 015d1de)
        pockets = {
            { angle = 90, width = 24 },
            { angle = 210, width = 24 },
            { angle = 330, width = 24 },
        },
    },

    -- Tables de combat : géométrie SIMULÉE par le serveur et modèle 3D correspondant (mêmes valeurs que
    -- tools/models/build_bowl.py, tests/bowl_variants_test.lua). Le moteur ne gère que R, h et les poches :
    -- pas de frottement propre à une table. Une station fixe choisit sa variante (data/arenas.json, champ variant).
    arenaVariants = {
        -- standard = testArena (renseignée juste après ce tableau)
        compact = {
            -- retour arrière : model = 'spin_arena_bowl_compact', floorHeight = 0.75, rOuter = 0.56
            label = 'Compacte', R = 0.46, h = 0.090, model = 'spin_arena_table_atelier', floorHeight = 0.780, rOuter = 0.626,
            pockets = { { angle = 90, width = 18 }, { angle = 270, width = 18 } },
        },
        ejection = {
            -- retour arrière : model = 'spin_arena_bowl_ejection', floorHeight = 0.75, rOuter = 0.70
            label = 'Éjection', R = 0.60, h = 0.055, model = 'spin_arena_table_prism', floorHeight = 0.820, rOuter = 0.796,
            pockets = { { angle = 45, width = 38 }, { angle = 135, width = 38 }, { angle = 225, width = 38 }, { angle = 315, width = 38 } },
        },
        glide = {
            -- retour arrière : model = 'spin_arena_bowl_glide', floorHeight = 0.75, rOuter = 0.78
            label = 'Large', R = 0.68, h = 0.045, model = 'spin_arena_table_vector', floorHeight = 0.760, rOuter = 0.856,
            pockets = { { angle = 90, width = 28 }, { angle = 210, width = 28 }, { angle = 330, width = 28 } },
        },
    },

    -- Texte de télémétrie à l'écran pendant un combat (w, wob, état) : débogage seulement ; le panneau au-dessus de
    -- chaque table affiche noms, score et manche
    debugTelemetry = false,

    -- Distance (m) à laquelle le décor d'une table fixe est posé chez le joueur ; au delà de 1,25 fois cette distance il est retiré.
    -- Une table (ou le hall d'une extension) loin de tout joueur ne coûte donc ni mémoire ni objets. 0 = toutes les tables, toujours.
    stationStreamRadius = 250.0,

    -- Pièces qui ont une icône dédiée dans ox_inventory/web/images (spin_part_<id>.png) : rempli avec les fichiers
    -- d'icônes (lot visuel). Purement visuel : ne change ni les identifiants ni les stats. Vide = image générique.
    -- Lot visuel : planche Money (install/icons_money/CORRESPONDANCE.md) et trois icônes originales ajoutées
    -- pour compléter les pièces manquantes du catalogue.
    partIcons = {
        ring_smash = true, ring_guard = true, ring_round = true, ring_std = true,
        ring_reverse = true,   -- 28/10 : icône de l'anneau standard, en miroir et teintée violet (à copier dans ox_inventory)
        frame_std = true, frame_wide = true, frame_low = true, frame_spike = true,
        core_std = true, core_rim = true, core_heavy = true, core_light = true,
        tip_flat = true, tip_sharp = true, tip_rubber = true, tip_std = true, tip_ball = true,
    },

    -- Deux toupies de test (formes temporaires en phase 1). Couleurs en RGB pour le rendu.
    testTops = {
        attack = {
            label = 'Prototype A (attaque)',
            family = 'attack',
            color = { 255, 85, 0 },
            stats = {
                m = 0.048, r = 0.050, kI = 0.55,
                atk = 0.8, def = 0.3, stab = 0.4,
                tipFric = 5.5, mob = 1.2, trac = 2.0, damp = 0.35,
                w0 = 260, v0 = 0.7, dir = 1,
            },
        },
        endurance = {
            label = 'Prototype E (endurance)',
            family = 'endurance',
            color = { 0, 229, 255 },
            stats = {
                m = 0.052, r = 0.048, kI = 0.65,
                atk = 0.2, def = 0.5, stab = 0.8,
                tipFric = 2.6, mob = 0.25, trac = 1.0, damp = 0.5,
                w0 = 240, v0 = 0.4, dir = 1,
            },
        },
    },
}

-- La table standard est l'arène historique (station actuelle, combats improvisés)
SpinArena.Config.testArena.label = SpinArena.Config.testArena.label or 'Standard'
SpinArena.Config.arenaVariants.standard = SpinArena.Config.testArena

-- Panneau du classement de saison (5 premiers) près des tables de Legion Square ; ancrage convenu avec Babbage,
-- à confirmer en jeu avec Fermi. nil = pas de panneau.
SpinArena.Config.leaderboardBoard = { x = 202.70, y = -900.11, z = 30.137, height = 2.8 }

return SpinArena.Config
