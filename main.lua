-- lua version
-- uses moonal and midialsa

local alsa = require("midialsa")
local snd = require("synth.snd")
local waves = require("synth.waves")

alsa.start()
local _ = alsa.client("LuaSynthesizer", 1, 1, true)
assert(alsa.connectfrom(0, alsa.parse_address(assert((...), "need midi device"))), "invalid midi device")

-- for 88-key piano: min pitch is 21 max is 100

local sustain
local held = {}
while true do
  local evt = alsa.input()
  if evt[1] == alsa.SND_SEQ_EVENT_NOTEON then
    local pitch = evt[8][2]
    held[pitch] = true
    local velocity = evt[8][3]
    local amp = velocity/128

    snd.startLoop(pitch, velocity, waves.getPCMString(waves.generatePCM(waves.generators.sine, snd.freq(pitch), amp)))

  elseif evt[1] == alsa.SND_SEQ_EVENT_NOTEOFF then
    local pitch = evt[8][2]
    held[pitch] = false
    if not sustain then
      snd.stopLoop(pitch, -1)
    end

  elseif evt[1] == alsa.SND_SEQ_EVENT_CONTROLLER then
    sustain = evt[8][6] > 63
    if not sustain then
      for i=0, 255 do
        if not held[i] then
          snd.stopLoop(i, -1)
        end
      end
    end
  end
end
