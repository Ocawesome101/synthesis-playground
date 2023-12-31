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
    if cur/max < 0.25 then -- 0 to 0.25
      return cur/max * 4
    elseif cur/max < 0.75 then -- 0.25 to 0.75
      return 1 - (cur/max - 0.25) * 4
    else
      return -1 + (cur/max - 0.75) * 4
    end
  end,
}

-- wave utility functions
function mod.phaseshift(generator, shift)
  return function(cur, max)
    return generator((cur + (max*shift)) % max, max)
  end
end

function mod.avg(...)
  local a = {...}
  local n = 0
  for i=1, #a do n = n + a[i] end
  return n/#a
end

function mod.abs(...)
  local a = {...}
  local n = 0
  for i=1, #a do
    if math.abs(a[i]) > math.abs(n) then n = a[i] end
  end
  return n
end

function mod.loadWave(file)
  local wave = {}
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
    samples[i] = generator(i, sampleCount)
  end
  return samples
end

function mod.generateSampledPCM(waveform, hz, amp)
  local buffer = {}

  local separation = floor(snd.SAMPLE_RATE/#waveform/hz+0.5)
  for i=1, #waveform*separation do
    local iReal = i/separation%#waveform
    if floor(iReal) == iReal then iReal = iReal + 0.1 end
    local iFore, iAft = floor(iReal), ceil(iReal)
    local diff = (waveform[iAft] or 0) - (waveform[iFore] or 0)
    buffer[i] = math.max(snd.SAMPLE_MIN,math.min(snd.SAMPLE_MAX,
      floor(((waveform[iAft]or 0) + diff*(iReal-iFore)) * snd.SAMPLE_MAX * amp)))
  end

  return buffer
end

function mod.generatePCM(generator, hz, amp)
  local buffer = {}

  local samples = snd.SAMPLE_RATE/hz
  for i=0, samples do
    buffer[i+1] = floor(generator(i, samples) * snd.SAMPLE_MAX * amp + 0.5)
  end

  return buffer
end

function mod.generatePCMPulse(generator, hz, ampStart, ampEnd, duration, linearity)
  linearity = linearity or 1
  local buffer = {}
  local samplesPerOscillation = floor(snd.SAMPLE_RATE/hz+0.5)
  local totalSamples = snd.SAMPLE_RATE*duration - (snd.SAMPLE_RATE*duration % samplesPerOscillation)

  for i=0, totalSamples do
    local current = i % samplesPerOscillation
    local amp = ampStart+(ampEnd-ampStart)*((i/totalSamples)^linearity)
    buffer[#buffer+1] = floor(math.max(-1, math.min(1,generator(current, samplesPerOscillation))) * snd.SAMPLE_MAX * amp + 0.5)
  end

  return buffer
end

function mod.generateSampledPCMPulse(waveform, hz, ampStart, ampEnd, duration, linearity)
  linearity = linearity or 1
  local buffer = {}
  local samplesPerOscillation = floor(snd.SAMPLE_RATE/hz+0.5)
  local totalSamples = snd.SAMPLE_RATE*duration - (snd.SAMPLE_RATE*duration % samplesPerOscillation)
  local separation = floor(snd.SAMPLE_RATE/#waveform/hz+0.5)

  for i=0, totalSamples do
    local amp = ampStart+(ampEnd-ampStart)*((i/totalSamples)^linearity)
    local iReal = i/separation%#waveform
    local iFore, iAft = floor(iReal-1), ceil(iReal)
    local diff = (waveform[iAft] or 0) - (waveform[iFore] or 0)
    buffer[#buffer+1] = floor(math.max(snd.SAMPLE_MIN,math.min(snd.SAMPLE_MAX,
      floor(((waveform[iAft]or 0) + diff*(iReal-iFore)) * amp * snd.SAMPLE_MAX))))
  end

  return buffer
end

function mod.getPCMString(buffer)
  local b = {}
  for i=1, #buffer do
    b[#b+1] = string.char(buffer[i]&0xFF)
    b[#b+1] = string.char((buffer[i]&0xFF00) >> 8)
  end
  return table.concat(b)
end

return mod
