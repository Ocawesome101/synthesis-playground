-- lua version
-- uses moonal and midialsa

local alsa = require("midialsa")
local snd = require("synth.snd")
local waves = require("synth.waves")
local noise = require("synth.noise")

alsa.start()
local _ = alsa.client("LuaSynthesizer", 1, 1, true)
assert(alsa.connectfrom(0, alsa.parse_address(assert((...), "need midi device"))), "invalid midi device")

-- for 88-key piano: min pitch is 21 max is 100

local samples = {
  -- drums
  -- kick
  waves.getPCMString(waves.generatePCMPulse(noise.noiseGenerator(), 220, 1, 0.1, 0.3, 1.3)),
  -- snare?
  waves.getPCMString(waves.generatePCMPulse(noise.noiseGenerator(), 440, 1, 0.1, 0.3, 1.3)),
  -- tom?
  waves.getPCMString(waves.generatePCMPulse(noise.noiseGenerator(), 880, 1, 0.1, 0.2, 1.4)),
  -- cymbal
  waves.getPCMString(waves.generatePCMPulse(noise.noiseGenerator(), 7000, 1, 0.1, 0.2, 1.5)),
  -- hi-hat (closed)
  waves.getPCMString(waves.generatePCMPulse(noise.noiseGenerator(), 9000, 0.5, 0.1, 0.1, 1.7)),
  -- hi-hat (open)
  waves.getPCMString(waves.generatePCMPulse(noise.noiseGenerator(), 9000, 0.7, 0.1, 0.2, 1.8)),
}

local fancy = function(a, b)
  return waves.abs(waves.phaseshift(waves.generators.sine, 0.1)(a,b), waves.generators.sine(a,b))
end
--[[
print'generating samples'
for i=#samples+1, 88 do
  print(i)
  samples[i] = waves.getPCMString(waves.generatePCMPulse(fancy, snd.freq(i+20), 1, 0.1, 1, 0.5))
end
print'done'--]]

local sustain
local channel = 1
local held = {}
while true do
  local evt = alsa.input()
  if evt[1] == alsa.SND_SEQ_EVENT_NOTEON then
    local pitch = evt[8][2]
    held[pitch] = true
    local velocity = evt[8][3]
    local amp = velocity/128

    if samples[pitch - 20] then
      snd.startNote(pitch, velocity, samples[pitch - 20], channel)
    else
      snd.startLoop(pitch, velocity, waves.getPCMString(waves.generatePCM(fancy, snd.freq(pitch), amp)), channel)
    end

  elseif evt[1] == alsa.SND_SEQ_EVENT_NOTEOFF then
    local pitch = evt[8][2]
    held[pitch] = false
    if not sustain then
      snd.stopLoop(pitch, channel)
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
