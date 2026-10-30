-- SPIN ARENA — catalogue des pièces (phase 4, refonte du 29/10), partagé : le client l'affiche, le serveur seul l'applique.
-- Chaque toupie a quatre étages : la Lame (contact, attaque/défense), le Noyau (masse et réserve de rotation), le
-- Verrou (hauteur, stabilité, résistance à l'éclatement : `burst`) et l'Embout (pointe, mobilité, accroche du rail
-- turbo : `dash`). Les clés internes (ring, core, frame, tip) ne changent pas : les toupies déjà assemblées restent
-- valides. Une pièce modifie les caractéristiques de base et coûte des points ; la somme ne dépasse pas le budget.
-- Les peintures sont purement cosmétiques et ne changent aucune caractéristique.
SpinArena = SpinArena or {}

SpinArena.Parts = {
    budget = 100,

    slots = { 'core', 'ring', 'frame', 'tip' },
    slotLabels = { core = 'Noyau', ring = 'Lame', frame = 'Verrou', tip = 'Embout' },

    -- Caractéristiques de départ, avant les pièces (docs/PHYSICS.md §4)
    base = {
        m = 0.050, r = 0.050, kI = 0.55,
        atk = 0.5, def = 0.5, stab = 0.5,
        tipFric = 4.2, mob = 0.7, trac = 1.5, damp = 0.35,
        w0 = 250, v0 = 0.55, dir = 1,
        burst = 0.5,   -- résistance du verrou à l'éclatement (0 fragile, 1 très solide)
        dash = 0.0,    -- accroche de l'embout sur le rail turbo (0 aucune, 1 maximale)
    },

    catalog = {
        -- Noyaux : masse et répartition (réserve de rotation)
        core_std   = { slot = 'core', label = 'Noyau standard', cost = 20, mods = {} },
        core_heavy = { slot = 'core', label = 'Noyau lesté', cost = 30, mods = { m = 0.006, kI = 0.05, w0 = -10 } },
        core_light = { slot = 'core', label = 'Noyau allégé', cost = 20, mods = { m = -0.004, kI = -0.03, mob = 0.2 } },
        core_rim   = { slot = 'core', label = 'Noyau à couronne', cost = 35, mods = { m = 0.004, kI = 0.08 } },
        -- Lames : forme du contact, attaque et défense
        ring_std   = { slot = 'ring', label = 'Lame Orbite', cost = 20, mods = {} },
        ring_smash = { slot = 'ring', label = 'Lame Griffe', cost = 30, mods = { atk = 0.4, def = -0.15 } },
        ring_guard = { slot = 'ring', label = 'Lame Rempart', cost = 30, mods = { def = 0.2, atk = -0.2, m = 0.004 } },
        ring_round = { slot = 'ring', label = 'Lame Galet', cost = 25, mods = { atk = -0.1, def = 0.1, stab = 0.1 } },
        -- Rotation gauche : `dir = -1` inverse le sens de la toupie (shared/stats.lua). Le moteur calcule déjà le
        -- glissement au contact avec le sens de chaque toupie : même sens = surfaces opposées, chocs durs ; sens
        -- contraires = surfaces qui roulent ensemble, contacts doux. Sans contrepartie, l'inversion seule gagnait
        -- presque tout (banc du 28/10) : réserve de rotation réduite (w0 −25). Mesures : docs/PHYSICS.md §19.
        ring_reverse = { slot = 'ring', label = 'Lame Contre-courant', cost = 20, dir = -1, mods = { w0 = -25 } },
        -- Verrous : nombre de crans (résistance à l'éclatement) et hauteur (stabilité)
        frame_std   = { slot = 'frame', label = 'Verrou 4 crans', cost = 15, mods = {} },
        frame_wide  = { slot = 'frame', label = 'Verrou large 5 crans', cost = 25, mods = { r = 0.006, stab = 0.15, mob = -0.1, burst = 0.1 } },
        frame_low   = { slot = 'frame', label = 'Verrou bas 6 crans', cost = 25, mods = { stab = 0.25, atk = -0.05, burst = 0.2 } },
        frame_spike = { slot = 'frame', label = 'Verrou à pics 3 crans', cost = 20, mods = { atk = 0.15, stab = -0.15, burst = -0.1 } },
        -- Embouts : endurance, mobilité et accroche du rail turbo (dash)
        tip_std    = { slot = 'tip', label = 'Embout Standard', cost = 20, mods = { dash = 0.3 } },
        tip_sharp  = { slot = 'tip', label = 'Embout Aiguille', cost = 30, mods = { tipFric = -1.0, mob = -0.45, trac = -0.5, damp = 0.15, stab = 0.1 } },
        tip_flat   = { slot = 'tip', label = 'Embout Plat', cost = 30, mods = { tipFric = 0.6, mob = 0.5, trac = 0.5, dash = 0.7 } },
        tip_ball   = { slot = 'tip', label = 'Embout Bille', cost = 25, mods = { tipFric = -0.6, def = 0.1, dash = 0.15 } },
        -- 30/10 : la gomme accroche (trac) sans freiner la rotation : son tipFric +0,5 faisait perdre la Mobilité au temps
        -- presque partout (tests/family_balance_test.lua)
        tip_rubber = { slot = 'tip', label = 'Embout Gomme', cost = 35, mods = { mob = 0.4, trac = 1.2, damp = -0.1, stab = 0.1, dash = 0.5 } },
    },

    -- Assemblages de départ, un par famille (budget respecté)
    kits = {
        attack    = { label = 'Attaque', parts = { core = 'core_light', ring = 'ring_smash', frame = 'frame_spike', tip = 'tip_flat' } },
        defense   = { label = 'Défense', parts = { core = 'core_heavy', ring = 'ring_guard', frame = 'frame_std', tip = 'tip_ball' } },
        endurance = { label = 'Endurance', parts = { core = 'core_rim', ring = 'ring_std', frame = 'frame_std', tip = 'tip_sharp' } },
        balance   = { label = 'Équilibre', parts = { core = 'core_std', ring = 'ring_round', frame = 'frame_low', tip = 'tip_ball' } },
        -- 30/10 : verrou large (100 points comme l'Attaque, la Défense et l'Endurance, au lieu de 90) : rayon et stabilité en plus
        mobility  = { label = 'Mobilité', parts = { core = 'core_light', ring = 'ring_std', frame = 'frame_wide', tip = 'tip_rubber' } },
    },

    -- Lanceurs (29/10) : même objet `spin_launcher`, le type est dans metadata.launcher. Le serveur applique l'effet au
    -- lancer ; le client ne fait qu'afficher. Le premier lanceur de l'inventaire (emplacement le plus bas) est celui
    -- utilisé en match. Chaque effet est un petit bonus assorti d'un défaut : aucun type n'est meilleur partout.
    --   spin  : bonus de rotation de départ (fraction)       speed : bonus de vitesse de départ (fraction)
    --   atk   : bonus d'attaque de la toupie (0..1)
    --   width : largeur de la zone de jauge (×)              pullMaxMs : fenêtre de tirage allongée de (ms)
    --   tilt  : effet de l'inclinaison du lanceur (×)        dash : accroche du rail turbo ajoutée à l'embout (0..1)
    launchers = {
        default = 'cord',
        order = { 'cord', 'crank', 'spring', 'precision', 'rail' },
        catalog = {
            cord      = { label = 'Lanceur Cordon', priceMult = 1.0, desc = 'Le lanceur de base, sans bonus ni défaut.' },
        },
    },

    -- Peintures (cosmétique seulement)
    paints = {
        titanium = { label = 'Titane', color = { 195, 202, 212 } },
        cyan = { label = 'Cyan électrique', color = { 0, 229, 255 } },
        orange = { label = 'Orange impact', color = { 255, 85, 0 } },
        graphite = { label = 'Graphite', color = { 70, 76, 86 } },
    },

    -- Usure : chaque match ajoute 1 ; au-delà de `wearFree`, la rotation de lancement baisse un peu
    wearFree = 10,
    wearPenalty = 0.005,   -- par point au-delà de wearFree
    wearMax = 40,
}

-- Édition gratuite : les lanceurs et pièces réservés à l'édition Pro sont retirés du fichier à la fabrication du paquet
-- (tools/package.py) ; l'ordre d'affichage ne garde que les lanceurs qui existent.
do
    local L, ordered = SpinArena.Parts.launchers, {}
    for _, id in ipairs(L.order) do
        if L.catalog[id] then ordered[#ordered + 1] = id end
    end
    L.order = ordered
end

return SpinArena.Parts
