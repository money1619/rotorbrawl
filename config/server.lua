-- SPIN ARENA — configuration serveur (jamais envoyée aux clients : déclarée seulement en server_scripts)
SpinArena = SpinArena or {}

SpinArena.ServerConfig = {
    -- Profils de toupies autorisés en phase 2 (clés de SpinArena.Config.testTops). La phase 4 les remplacera
    -- par les toupies possédées (uid vérifié en base et dans l'inventaire).
    allowedTops = { attack = true, endurance = true },
    -- Profils de test (toupies prêtées) : INTERDITS aux joueurs. Un combat exige une toupie complète possédée.
    -- Mettre à true seulement sur une instance de test ; /spin_test (admin) n'en dépend pas.
    allowTestProfiles = false,
    requireLauncher = true,       -- matériel réel requis pour les matchs joueurs

    match = {
        winsNeeded = 2,            -- 2 manches gagnantes (mode 'rounds')
        -- Règles par points (29/10) : chaque manche rapporte des points selon la finition, le premier à `target` gagne.
        -- SORTIE (éjection) = 2, ARRÊT (rotation épuisée) = 1, ÉCLAT (verrou cédé) = 2, TURBO (éjection après un
        -- choc venu du rail turbo) = 3. mode = 'rounds' : ancien décompte en manches gagnées.
        scoring = { mode = 'points', target = 4, maxRounds = 7,
                    points = { ring_out = 2, spin_out = 1, burst = 2, turbo_out = 3, default = 1 } },
        maxRounds = 5,             -- égalités comprises ; au-delà : victoire au score, sinon match nul
        countdownMs = 3000,
        intermissionMs = 4000,     -- pause entre la fin d'une manche et l'en-tête de la suivante
        leadMs = 500,              -- avance de diffusion des tranches ordinaires
        endGraceMs = 500,          -- marge après la fin calculée avant de publier roundEnd
        maxConcurrent = 8,         -- matchs simultanés sur le serveur
        stateTimeoutMs = 120000,   -- garde-fou : aucun état ne dure plus longtemps
        -- Lancement manuel : chaque manche attend que les DEUX joueurs aient armé leur lanceur et réussi la jauge.
        -- false = départ automatique (démonstration et anciens tests seulement) ; jamais pour un vrai duel.
        manualLaunch = true,
        prepareMs = 30000,         -- délai de préparation d'une manche (doit rester < stateTimeoutMs)
        -- Délai dépassé : manche 1 → match annulé, sans résultat. Manches suivantes : 'forfeit_round' (le côté
        -- qui n'a pas lancé perd la manche ; aucun des deux → match sans résultat) ou 'no_contest'.
        prepareTimeout = 'forfeit_round',
        -- Entraînement admin (/spin_test pratique) : l'adversaire simulé lance seul, qualité fixe (0,5 = neutre)
        practice = { botLaunchMs = 2500, botQuality = 0.5 },
        launch = {
            armTtlMs = 30000,      -- validité d'un armement (nonce à usage unique) = prepareMs : viser longtemps ne
                                   -- demande pas de rappuyer (décision de Money, 19/10) ; le délai de la manche reste
                                   -- l'échéance qui fait foi (pas de relance automatique)
            minHoldMs = 400,       -- relâcher plus tôt est refusé (il faut réarmer)
            periodMinMs = 1100,    -- période de l'aiguille, tirée par le serveur à chaque armement
            periodMaxMs = 1700,
            width = 0.30,          -- écart à la cible (0..1) au-delà duquel la qualité vaut 0
            maxLatencyCompMs = 250, -- compensation = ping mesuré par le serveur, plafonné
            -- Lanceur à tirette : 1) prise (la jauge ci-dessus), 2) tirage = durée entre prise et relâchement.
            -- Sans prise (appui rapide), le tirage compte 0 : le lancer plafonne à gripWeight (« bon »).
            gripWeight = 0.55,     -- part de la prise dans la qualité ; le tirage pèse le reste
            pullMinMs = 150,       -- tirage idéal : de pullMinMs à pullMaxMs après la prise
            pullMaxMs = 450,
            pullFadeMs = 600,      -- au-delà de pullMaxMs, la qualité tombe à 0 sur cette durée
            -- Effet du lancer, mesuré sur le moteur (tests/launch_unit_test.lua, 48 manches par cas) : la rotation
            -- de départ décide presque seule des manches (dès ±2 % un favori s'inverse, mesuré le 28/10), d'où ±1 % ;
            -- la vitesse de départ pèse peu : ±15 % passent le test (±5 % avant), ±25 % aussi.
            -- Plus fort sur la rotation : un bon lancer renverse les archétypes.
            spinGain = 0.01,       -- rotation de départ (w0) : ±1 %
            speedGain = 0.15,      -- vitesse de départ (v0) : ±15 %
        },
    },

    challenge = {
        ttlMs = 30000,             -- un défi expire après 30 s
        maxIncoming = 3,           -- défis reçus en attente par joueur
        maxDistance = 10.0,        -- distance maximale entre les deux joueurs (m)
    },

    arena = {
        distanceInFront = 2.5,     -- l'arène improvisée est posée devant le joueur qui défie (m)
        pedToGround = 0.98,        -- hauteur approximative du ped au-dessus du sol (m)
        minGap = 1.5,              -- écart minimal entre deux arènes actives, en plus de leurs rayons (m)
        watchRadius = 25.0,        -- spectateurs et zone de jeu (m)
        maxSpectators = 16,
        maxWatched = 4,            -- matchs suivis à la fois par un joueur (tables voisines), son propre match compris
        audienceRefreshMs = 1000,
        fixedRadius = 15.0,        -- un défi utilise l'arène fixe libre la plus proche dans ce rayon (m)
        improvisedAnywhere = true, -- arène improvisée partout ; false = seulement dans les zones autorisées
        dataFile = 'data/arenas.json',
        -- Arènes fixes posées par la config (en plus de celles créées en jeu avec /spin_admin arena add) :
        -- { name = 'plage', x = -1600.0, y = -1100.0, z = 13.0, heading = 90.0, bucket = 0, variant = 'turbo' }
        -- variant : standard (par défaut) ou une variante de config/shared.lua arenaVariants. Retrait : supprimer la ligne.
        fixedList = {
        },
        maxZoneRadius = 200.0,
    },

    rules = {
        onDeath = 'forfeit',       -- 'forfeit' (défaite) ou 'no_contest' (match sans résultat), voir ARCHITECTURE.md §11
        leaveGraceMs = 5000,       -- délai hors de la zone (ou en véhicule) avant l'abandon
    },

    -- Limites de fréquence par joueur : capacité du seau et recharge (jetons par seconde)
    rateLimits = {
        challenge = { burst = 2, perSecond = 1 / 3 },
        respond = { burst = 3, perSecond = 2 },
        cancel = { burst = 3, perSecond = 2 },
        forfeit = { burst = 3, perSecond = 2 },
        state = { burst = 5, perSecond = 4 },
        leaderboard = { burst = 2, perSecond = 0.5 },
        tops = { burst = 3, perSecond = 1 },
        workshop = { burst = 3, perSecond = 1 },
        shop = { burst = 3, perSecond = 1 },
        shopBuy = { burst = 3, perSecond = 1 },
        queueJoin = { burst = 2, perSecond = 0.5 },
        queueLeave = { burst = 3, perSecond = 1 },
        launchArm = { burst = 3, perSecond = 1 },
        launchGrip = { burst = 3, perSecond = 1 },
        launchRelease = { burst = 3, perSecond = 1 },
        tournamentCreate = { burst = 1, perSecond = 0.1 },
        tournamentJoin = { burst = 2, perSecond = 0.5 },
        tournamentLeave = { burst = 2, perSecond = 0.5 },
        tournamentStatus = { burst = 3, perSecond = 1 },
        global = { burst = 15, perSecond = 10 },
    },

    -- Classement (phase 6) : cote Elo par saison
    ranking = {
        season = 1,
        k = 24,
        start = 1000,
        minForfeitMs = 30000,      -- un forfait plus rapide ne compte pas
        top = 20,
    },

    -- Homologation (server/homologation.lua) : seuls les matchs homologués comptent au classement ; les autres sont amicaux.
    -- Un match homologué reçoit un certificat signé (clé : data/homologation.key, ou convar spin_arena_homologation_key).
    homologation = {
        enabled = true,
        arenaKinds = { fixed = true },   -- tables où un match peut être homologué : fixed (config ou /spin_admin), portable, improvised
        allowTestTops = false,           -- toupies de test (match.allowedTops) : amical seulement
        pairPerHour = 6,                 -- matchs homologués au plus entre les deux mêmes joueurs sur une heure (anti-complaisance)
    },

    -- Boutique (boutique native d'ox_inventory) : un point de vente à chaque arène fixe et aux emplacements listés
    shop = {
        enabled = true,
        anywhere = false,          -- achats uniquement près d’un point de vente serveur
        includeFixedArenas = false, -- une station de combat n’est pas une boutique
        locations = {
            { x = 195.5982, y = -902.1155, z = 31.1168, heading = 314.2403,
              label = 'Legion Square', ped = 's_m_m_autoshop_01' },
        },
        currency = 'money',        -- objet ox_inventory débité à l'achat (argent liquide ESX avec ox_inventory)
        maxCount = 10,             -- quantité maximale par achat pour les objets empilables
        prices = {
            top = 2500,
            launcher = 800,
            partBase = 150,        -- prix d'une pièce = partBase + partPerPoint × son coût en points
            partPerPoint = 20,
            repair = 300,
        },
    },

    -- Tournois (phase 6) : élimination directe, rencontres lancées quand les deux joueurs sont sur place
    tournaments = {
        organizerAce = 'spin_arena.organizer',
        venueRadius = 15.0,        -- distance maximale de chaque joueur au lieu de la rencontre (m)
        presenceTimeoutMs = 180000, -- absent plus longtemps : forfait
        maxReplays = 1,            -- rencontres rejouées après une annulation ou un match nul
        maxActive = 2,             -- tournois simultanés
    },

    adminAce = 'spin_arena.admin',
    debugLog = false,
}

return SpinArena.ServerConfig
