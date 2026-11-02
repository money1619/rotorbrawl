-- ROTORBRAWL — panneau d'administration en jeu : /spin_panel (menu ox_lib). Voir server/admin_panel.lua (le serveur vérifie les droits).
SpinArena = SpinArena or {}

local Panel = {}
SpinArena.AdminPanelClient = Panel

local function notify(text, kind)
    if type(lib) == 'table' and lib.notify then lib.notify({ title = 'ROTORBRAWL', description = text, type = kind or 'inform' }) end
end

local function refresh() Panel.open() end

local function confirmAct(label, kind, id)
    local sure = lib.alertDialog({ header = label, content = 'Confirmer ?', centered = true, cancel = true })
    if sure ~= 'confirm' then return refresh() end
    local res = lib.callback.await('spin_arena:admin:act', false, { kind = kind, id = id })
    notify(res and res.message or 'pas de réponse', res and res.ok and 'success' or 'error')
    refresh()
end

function Panel.menus(snap)
    local main = {}
    local function sub(idName, title, options)
        if #options == 0 then options[1] = { title = 'Rien pour le moment', disabled = true } end
        options[#options + 1] = { title = 'Retour', icon = 'arrow-left', menu = 'spin_panel' }
        lib.registerContext({ id = idName, title = title, menu = 'spin_panel', options = options })
    end
    local matches, tours, arenas = {}, {}, {}
    for _, m in ipairs(snap.matches) do
        matches[#matches + 1] = {
            title = ('%s contre %s'):format(m.a, m.b), description = ('manche %d, score %s, %s%s'):format(m.round, m.score, m.state, m.practice and ', entraînement' or ''),
            icon = 'circle-xmark', onSelect = function() confirmAct('Annuler le match ' .. m.id, 'cancel_match', m.id) end,
        }
    end
    for _, t in ipairs(snap.tournaments) do
        tours[#tours + 1] = {
            title = ('%s (%s)'):format(t.name, t.state), description = ('%d / %d joueurs · cliquer pour %s'):format(t.players, t.size, t.state == 'signup' and 'lancer' or 'annuler'),
            icon = 'trophy', onSelect = function()
                if t.state == 'signup' then confirmAct('Lancer le tournoi ' .. t.name, 'tournament_start', t.id)
                else confirmAct('Annuler le tournoi ' .. t.name, 'tournament_cancel', t.id) end
            end,
        }
    end
    for _, a in ipairs(snap.arenas) do
        arenas[#arenas + 1] = {
            title = a.name, description = ('variante %s%s'):format(a.variant, a.fromConfig and ' · vient de la config ou d\'une extension (non supprimable ici)' or ''),
            icon = 'table', disabled = a.fromConfig,
            onSelect = function() confirmAct('Supprimer l\'arène ' .. a.name, 'arena_remove', a.name) end,
        }
    end
    sub('spin_panel_matches', 'Matchs en cours', matches)
    sub('spin_panel_tours', 'Tournois', tours)
    sub('spin_panel_arenas', 'Arènes fixes', arenas)
    main[#main + 1] = { title = ('Matchs en cours (%d)'):format(#snap.matches), icon = 'swords', menu = 'spin_panel_matches' }
    main[#main + 1] = { title = ('Tournois (%d)'):format(#snap.tournaments), icon = 'trophy', menu = 'spin_panel_tours' }
    main[#main + 1] = { title = ('Arènes fixes (%d)'):format(#snap.arenas), icon = 'table', menu = 'spin_panel_arenas' }
    main[#main + 1] = {
        title = ('Achats non résolus : %d'):format(snap.unresolved), icon = 'receipt', disabled = true,
        description = snap.unresolved > 0 and 'À régulariser : commande /spin_admin achats dans la console' or 'Aucun',
    }
    main[#main + 1] = { title = 'Actualiser', icon = 'rotate', onSelect = refresh }
    lib.registerContext({ id = 'spin_panel', title = 'ROTORBRAWL — administration', options = main })
end

function Panel.open()
    local snap = lib.callback.await('spin_arena:admin:snapshot', false)
    if not snap then return notify('Droits insuffisants (ACE spin_arena.admin).', 'error') end
    Panel.menus(snap)
    lib.showContext('spin_panel')
end

if type(RegisterCommand) == 'function' then
    RegisterCommand('spin_panel', function() Panel.open() end, false)
end

return Panel
