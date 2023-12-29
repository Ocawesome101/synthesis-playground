-- lua version
-- uses moonal and midialsa

local alsa = require("midialsa")
local al = require("moonal")
local A4=440

local function freq(note)
  return A4 * 2^((note-69)/12)
end

alsa.start()
local _ = alsa.client("LuaSynthesizer", 1, 1, true)
assert(alsa.connectfrom(0, alsa.parse_address(...)))

local held = {}

local function doSynth()
  local buffer = {}
  for note in pairs(held) do
  end
end

while true do
  doSynth()
  local evt = alsa.input()
  if evt[1] == alsa.SND_SEQ_EVENT_NOTEON then
    local pitch = evt[8][2]
    held[pitch] = true

  elseif evt[1] == alsa.SND_SEQ_EVENT_NOTEOFF then
    local pitch = evt[8][2]
    held[pitch] = false
  end
end
