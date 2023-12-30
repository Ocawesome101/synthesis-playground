-- lua version
-- uses moonal and midialsa

local alsa = require("midialsa")
local al = require("moonal")
local A4=440

alsa.start()
local _ = alsa.client("LuaSynthesizer", 1, 1, true)
assert(alsa.connectfrom(0, alsa.parse_address(assert(..., "need midi device"))), "invalid midi device")

local held = {}

local wfSine = {}

for i=1, 32 do
  wfSine[#wfSine+1] = math.sin(math.pi*i/16) * 30000
end

local SAMPLE_MIN = -32768
local SAMPLE_MAX = 32767
local SAMPLE_RATE = 48000

local function freq(note)
  return A4 * 2^((note-69)/12)
end

local floor, ceil = math.floor, math.ceil
local sampleBuffer = {}
local waves = {}
-- generate one cycle of a waveform at a given hz
local function wavAtHz(waveform, hz, amp)
  local buffer = {}

  local separation = SAMPLE_RATE/#waveform/hz
  for i=1, #waveform*separation do
    local iReal = i/separation%#waveform
    local iFore, iAft = floor(iReal-1), ceil(iReal)
    local diff = (waveform[iAft] or 0) - (waveform[iFore] or 0)
    buffer[i] = math.max(SAMPLE_MIN,math.min(SAMPLE_MAX,
      floor(((waveform[iAft]or 0) + diff*(iReal-iFore)) * amp)))
  end

  return buffer
end

local generators = {
  sine = function(cur, max)
    local abs = cur/max * 2 * math.pi
    return math.sin(abs) / (math.pi/2) * (SAMPLE_MAX-4)
  end,
  square = function(cur, max)
    return (cur*2 >= max and SAMPLE_MAX or SAMPLE_MIN)
  end,
  saw = function(cur, max)
    return (cur*2 >= max and cur/max*SAMPLE_MAX or SAMPLE_MIN)
  end,
  triangle = function(cur, max)
    local period = max/4
    if cur < period then
      return cur/max*SAMPLE_MAX
    elseif cur < period*3 then
      return (cur-period)/max*SAMPLE_MAX*2-SAMPLE_MIN-1
    else
      return SAMPLE_MIN+(cur-period*3)/max*SAMPLE_MAX
    end
  end
}

local function genWavHz(generator, hz, amp)
  local buffer = {}

  local samples = SAMPLE_RATE/hz
  for i=0, samples do
    buffer[i] = math.floor(generator(i, samples) + 0.5)
  end

  return buffer
end

local function getPCM(thing, hz, amp)
  local buffer = genWavHz(generators.triangle, hz, amp)
  local s = ""
  for i=1, #buffer do
    s = s .. string.pack("<i2", buffer[i])
  end
  return s
end

local function merge(m)
  local buffer = {}
  for i=1, #m[1] do
    local sum = 0
    for n=1, #m do
      sum = sum + m[n][i]
    end
    buffer[i] = math.floor(sum / #m)
  end
  return buffer
end

local device = al.open_device()
local context = al.create_context(device)

local sources = {}
local buffers = {}
local notes = {}

local function doSynth()
  local sourceIndex = 0
  for _, note in pairs(held) do
    sourceIndex = sourceIndex + 1
    if notes[sourceIndex] ~= note then
      notes[sourceIndex] = note
      local source, buffer = sources[sourceIndex], buffers[sourceIndex]
      if sources[sourceIndex] then
        source:stop()
        source:delete()
      end
      source = al.create_source(context)
      sources[sourceIndex] = source
      source:set("looping", true)
      --if buffers[sourceIndex] then
      --  source:unqueue_buffers(1)
      --  buffers[sourceIndex]:delete()
      --end
      buffer = al.create_buffer(context)
      buffers[sourceIndex] = buffer
      buffer:data('mono16', getPCM(wfSine, freq(note), 1), SAMPLE_RATE)
      source:queue_buffers({buffer})
      source:play()
    end
  end
  for i=sourceIndex+1, #sources do
    notes[i] = nil
    sources[i]:stop()
    sources[i]:delete()
    sources[i] = nil
  end
end

local function addHeld(pitch)
  for i=1, #held do
    if held[i] == pitch then return end
  end
  held[#held+1] = pitch
end

local function removeHeld(pitch)
  for i=1, #held do
    if held[i] == pitch then return table.remove(held, i) end
  end
end

while true do
  doSynth()
  local evt = alsa.input()
  if evt[1] == alsa.SND_SEQ_EVENT_NOTEON then
    local pitch = evt[8][2]
    addHeld(pitch)

  elseif evt[1] == alsa.SND_SEQ_EVENT_NOTEOFF then
    local pitch = evt[8][2]
    removeHeld(pitch)
  end
end
