-- Flightpath Legends - SHA-256 (used to seal a hidden Battleship fleet: the hash is sent
-- before the battle and the fleet is revealed afterwards, so nobody can move ships or lie
-- about hits). Plain Lua 5.1 with the game's "bit" library.
local _, ns = ...

local H = {}
ns.Hash = H

local band, bor, bxor, bnot = bit.band, bit.bor, bit.bxor, bit.bnot
local rshift, lshift = bit.rshift, bit.lshift
local floor = math.floor
local MOD = 4294967296

local K = {
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
}

-- bit ops may return signed 32-bit numbers; keep everything as 0..2^32-1.
local function U(x) return x % MOD end
local function ror(x, n) return U(bor(rshift(x, n), lshift(x, 32 - n))) end

local function Block(h, w)
    for i = 17, 64 do
        local a, b = w[i - 15], w[i - 2]
        local s0 = bxor(ror(a, 7), ror(a, 18), rshift(a, 3))
        local s1 = bxor(ror(b, 17), ror(b, 19), rshift(b, 10))
        w[i] = U(w[i - 16] + U(s0) + w[i - 7] + U(s1))
    end
    local a, b, c, d, e, f, g, hh = h[1], h[2], h[3], h[4], h[5], h[6], h[7], h[8]
    for i = 1, 64 do
        local S1 = U(bxor(ror(e, 6), ror(e, 11), ror(e, 25)))
        local ch = U(bxor(band(e, f), band(bnot(e), g)))
        local t1 = U(hh + S1 + ch + K[i] + w[i])
        local S0 = U(bxor(ror(a, 2), ror(a, 13), ror(a, 22)))
        local maj = U(bxor(band(a, b), band(a, c), band(b, c)))
        local t2 = U(S0 + maj)
        hh, g, f, e, d, c, b, a = g, f, e, U(d + t1), c, b, a, U(t1 + t2)
    end
    h[1], h[2], h[3], h[4] = U(h[1] + a), U(h[2] + b), U(h[3] + c), U(h[4] + d)
    h[5], h[6], h[7], h[8] = U(h[5] + e), U(h[6] + f), U(h[7] + g), U(h[8] + hh)
end

-- SHA-256 of a string, as 64 lowercase hex characters.
function H.SHA256(msg)
    local len = #msg
    -- padding: 0x80, zeros, 64-bit big-endian length in bits
    local bits = len * 8
    local tail = { "\128" }
    local zeros = (55 - len) % 64
    tail[2] = string.rep("\0", zeros)
    local lenBytes = {}
    for i = 8, 1, -1 do
        lenBytes[i] = string.char(bits % 256)
        bits = floor(bits / 256)
    end
    msg = msg .. table.concat(tail) .. table.concat(lenBytes)
    local h = { 0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19 }
    local w = {}
    for chunk = 1, #msg, 64 do
        for i = 0, 15 do
            local p = chunk + i * 4
            local b1, b2, b3, b4 = string.byte(msg, p, p + 3)
            w[i + 1] = ((b1 * 256 + b2) * 256 + b3) * 256 + b4
        end
        Block(h, w)
    end
    local out = {}
    -- two 16-bit halves: formatting numbers >= 2^31 with %x is not portable
    for i = 1, 8 do out[i] = string.format("%04x%04x", floor(h[i] / 65536), h[i] % 65536) end
    return table.concat(out)
end

-- A random salt (hex), so nobody can guess a fleet from its hash.
function H.Salt(n)
    local t = {}
    for i = 1, (n or 16) do t[i] = string.format("%x", math.random(0, 15)) end
    -- mix in the clock so two players never draw the same salts
    return table.concat(t) .. string.format("%x", floor((debugprofilestop and debugprofilestop() or 0) * 1000) % 65536)
end
