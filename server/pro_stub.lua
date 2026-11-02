-- ROTORBRAWL, édition gratuite : les tournois et l'homologation des matchs font partie de l'édition Pro.
-- Ce fichier remplace server/tournaments.lua et server/homologation.lua dans le paquet gratuit (tools/package.py).
-- Sans module d'homologation, le classement compte tous les matchs avec résultat, comme avant.
SpinArena = SpinArena or {}

local function proOnly() return { ok = false, code = SpinArena.Protocol.codes.pro_only } end

SpinArena.Tournaments = {
    create = proOnly, join = proOnly, leave = proOnly, status = proOnly,
    onPlayerLeft = function() end,
    admin = function(_, _, reply) if reply then reply('les tournois font partie de l\'édition Pro') end end,
}

return SpinArena.Tournaments
