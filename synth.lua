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

  local s = ""
  for i=1, #buffer do
    s = s .. string.pack("<i2", buffer[i])
  end
  return s
  --return buffer
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
      buffer:data('mono16', wavAtHz(wfSine, freq(note), 1), SAMPLE_RATE)
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
