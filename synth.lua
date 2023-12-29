-- lua version
-- uses moonal and midialsa

local alsa = require("midialsa")
local A4=440

local function freq(note)
  return A4 * 2^((note-69)/12)
end

alsa.start()
local _ = alsa.client("LuaSynthesizer", 1, 1, true)
local cn2name = alsa.listclients()
for i=1, #cn2name do print(cn2name[i]) end
if #cn2name == 0 then error("no midi clients found", 0) end
assert()
