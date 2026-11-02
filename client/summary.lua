-- ROTORBRAWL — résumé de fin de match (web/match_summary.js). Données serveur uniquement (matchEnd.summary,
-- contrat proposé à Archimedes) ; affiché chez les duellistes seulement (champ side du message), sans focus.
SpinArena = SpinArena or {}
local S = {}
local P = SpinArena.Protocol or {}
local EV_END = (P.ev and P.ev.matchEnd) or 'spin_arena:cl:matchEnd'

function S.onMatchEnd(payload)
    if type(payload) ~= 'table' or (payload.side ~= 1 and payload.side ~= 2) then return false end   -- joueurs autour : panneau
    if type(SendNUIMessage) ~= 'function' then return false end
    SendNUIMessage({ action = 'matchSummary', winner = payload.winner, reason = payload.reason, score = payload.score,
                     names = payload.names, side = payload.side, summary = payload.summary, holdMs = 8000 })
    return true
end

if type(AddEventHandler) == 'function' then
    AddEventHandler(EV_END, S.onMatchEnd)
    AddEventHandler('onResourceStop', function(name)
        if name == (GetCurrentResourceName and GetCurrentResourceName()) and type(SendNUIMessage) == 'function' then
            SendNUIMessage({ action = 'matchSummaryClose' })
        end
    end)
end

SpinArena.Summary = S
return S
