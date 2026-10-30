-- Générateur pseudo-aléatoire du moteur : xorshift64* initialisé par splitmix64.
-- Un état par manche, indépendant de math.random (dont l'état est partagé par toute la ressource).
-- Lua 5.4 standard : entiers 64 bits, multiplication modulo 2^64, >> logique.
SpinArena = SpinArena or {}

local Rng = {}
Rng.__index = Rng

local function splitmix64(x)
    x = x + 0x9E3779B97F4A7C15
    x = (x ~ (x >> 30)) * 0xBF58476D1CE4E5B9
    x = (x ~ (x >> 27)) * 0x94D049BB133111EB
    return x ~ (x >> 31)
end

function Rng.new(seed)
    if math.type(seed) ~= 'integer' then
        error('Rng.new: seed must be an integer', 2)
    end
    local state = splitmix64(seed)
    if state == 0 then state = 0x9E3779B97F4A7C15 end
    return setmetatable({ state = state }, Rng)
end

function Rng:nextInt()
    local x = self.state
    x = x ~ (x >> 12)
    x = x ~ (x << 25)
    x = x ~ (x >> 27)
    self.state = x
    return x * 0x2545F4914F6CDD1D
end

-- Flottant dans [0, 1) avec 53 bits de précision
function Rng:next()
    return (self:nextInt() >> 11) * 0x1.0p-53
end

function Rng:range(a, b)
    return a + (b - a) * self:next()
end

-- Loi approximativement normale centrée réduite (somme de 4 uniformes, sans fonction de la libm)
function Rng:normal()
    local s = self:next() + self:next() + self:next() + self:next()
    return (s - 2) * 1.7320508075688772
end

SpinArena.Rng = Rng
return Rng
