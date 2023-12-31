-- lua version
-- uses moonal and midialsa

local snd = require("synth.snd")

local mod = {}
mod.waves = {}
-- generators return a value in the range [-1,1]
mod.generators = {
  sine = function(cur, max)
    local abs = cur/max * 2 * math.pi
    return math.sin(abs)
  end,
  square = function(cur, max)
    return (cur*2 >= max and 1 or -1)
  end,
  saw = function(cur, max)
    return (cur*2 >= max and cur/max or -1)
  end,
  triangle = function(cur, max)
    local amp = 1
    return 4*amp/max * math.abs((((cur-max/4)%max)+max)%max - max/2) - amp
  end,
}

function mod.loadWave(file)
  for line in io.lines(file) do
    wave[#wave+1] = tonumber(line)
  end
  return wave
end

local floor, ceil = math.floor, math.ceil

-- generate sampled wave from a generator
-- may be desirable for slight sound differences
function mod.generateSampledWave(generator, sampleCount)
  local samples = {}
  for i=1, sampleCount do
    samples[i] = generator(i/sampleCount)
  end
  return samples
end

function mod.sampledPCM(waveform, hz, amp)
  local buffer = {}

  local separation = mod.SAMPLE_RATE/#waveform/hz
  for i=1, #waveform*separation do
    local iReal = i/separation%#waveform
    local iFore, iAft = floor(iReal-1), ceil(iReal)
    local diff = (waveform[iAft] or 0) - (waveform[iFore] or 0)
    buffer[i] = math.max(SAMPLE_MIN,math.min(SAMPLE_MAX,
      floor(((waveform[iAft]or 0) + diff*(iReal-iFore)) * amp)))
  end

  return buffer
end

function mod.avg(...)
  local a = {...}
  local n = 0
  for i=1, #a do n = n + a[i] end
  return n/#a
end

function mod.generatePCM(generator, hz, amp)
  local buffer = {}

  local samples = SAMPLE_RATE/hz
  for i=0, samples do
    buffer[i+1] = math.floor(generator(i, samples) * mod.SAMPLE_MAX * amp + 0.5)
  end

  return buffer
end

function mod.getPCMString(hz, amp, duration)
  local buffer
  if generate then
    buffer = genWavHz(generators[wave], hz, amp, duration)
  else
    buffer = wavAtHz(wave, hz, amp, duration)
  end
  local s = ""
  for i=1, #buffer do
    s = s .. string.pack("<i2", buffer[i])
  end
  return s
end

return mod
