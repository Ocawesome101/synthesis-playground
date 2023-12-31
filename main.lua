-- lua version
-- uses moonal and midialsa

local alsa = require("midialsa")
local snd = require("synth.snd")
local waves = require("synth.waves")
local noise = require("synth.noise")
local loops = require("synth.loops")
local time = require("posix.time")

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
  return waves.abs(waves.phaseshift(waves.generators.sine, 0.3)(a,b), waves.generators.sine(a,b))
end
-- [[
print'generating samples'
for i=#samples+1, 88 do
  print(i)
  samples[i] = waves.getPCMString(waves.generatePCMPulse(fancy, snd.freq(i+20), 1, 0.1, 1, 0.5))
end
print'done'--]]

local sustain
local inLoop = false
local held = {}

local function begin(pitch, velocity, channel)
  local amp = velocity/128

  if samples[pitch - 20] then
    snd.startNote(pitch, velocity, samples[pitch - 20], channel)
  else
    snd.startLoop(pitch, velocity, waves.getPCMString(waves.generatePCM(fancy, snd.freq(pitch), amp)), channel)
  end
end

local channel = 0
local loopRunning = {}
while true do
  if alsa.inputpending() > 0 then
    local evt = alsa.input()
    if evt[1] == alsa.SND_SEQ_EVENT_NOTEON then
      local pitch = evt[8][2]
      held[pitch] = true
      local velocity = evt[8][3]

      begin(pitch, velocity, channel)
      if inLoop then
        loops.startNote(pitch, velocity)
      end

    elseif evt[1] == alsa.SND_SEQ_EVENT_NOTEOFF then
      local pitch = evt[8][2]
      held[pitch] = false
      if not sustain then
        snd.stopLoop(pitch, channel)
        if inLoop then
          loops.endNote(pitch)
        end
      end

    elseif evt[1] == alsa.SND_SEQ_EVENT_CONTROLLER then
      local pedal = evt[8][5]
      local pressed = evt[8][6]
      if pedal == 67 then
        if pressed > 63 then
          inLoop = true
          loops.startLoop()
        else
          inLoop = false
          local id = loops.endLoop()
          if id then loops.playLoop(id) end
        end
      else
        sustain = pressed > 63
        if not sustain then
          for i=0, 255 do
            if not held[i] then
              snd.stopLoop(i, -1)
            end
          end
        end
      end
    end
  end
  local frames, timeToNext = loops.nextFrame()
  if #frames > 0 then
    for i=1, #frames do
      local frame = frames[i]
      local running = {}
      for i=1, #frame.pitches do
        running[frame.pitches[i]] = true
        if loopRunning[frame.pitches[i]] ~= frame.velocities[i] then
          loopRunning[frame.pitches[i]] = frame.velocities[i]
          begin(frame.pitches[i], frame.velocities[i], frame.channel)
        end
      end
      for i=0, 255 do
        if not running[i] then
          snd.stopLoop(i, frame.channel)
        end
      end
    end
  end
  local absoluteTimeToNext = loops.getTime() + timeToNext
  repeat
    time.nanosleep({tv_sec=0,tv_nsec=math.min(timeToNext, 16)*1000000})
  until alsa.inputpending() > 0 or loops.getTime() >= absoluteTimeToNext
end
