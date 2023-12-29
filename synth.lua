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
  wfSine[#wfSine+1] = math.sin(math.pi*i/16) * 120
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
local function atHz(waveform, hz)
  waves[hz] = waves[hz] or {}
  if not waves[hz][waveform] then
    local buffer = {}

    local separation = SAMPLE_RATE/#waveform/hz
    for i=1, #waveform*separation do
      local iReal = i/separation%#waveform
      local iFore, iAft = floor(iReal-1), ceil(iReal)
      local diff = (waveform[iAft] or 0) - (waveform[iFore] or 0)
      buffer[i] = math.max(SAMPLE_MIN,math.min(SAMPLE_MAX,
        floor(((waveform[iAft]or 0) + diff*(iReal-iFore)))))
    end

    waves[hz][waveform] = buffer
  end
  return waves[hz][waveform]
end

local function wavAtHz(waveform, hz, amp, frameOffset, frames)
  hz = hz or 440
  amp = amp or 1
  -- waveforms are repeated once per hz
  -- each waveform is N samples
  -- sample rate is 48KHz
  -- with waveform length 32:
  -- at 1hz, each point should be 1500 samples apart
  -- at 100hz, each point should be 15 samples apart
  -- points are interpolated linearly for now
  -- this function returns N frames of
  --  audio at 'hz' hz with amplitude 'amp'
  local buffer = {}
  local wave = atHz(waveform, hz)
  for i=1, frames do
    buffer[#buffer+1] = floor(wave[(i%#wave) + 1] * amp)
  end
  return buffer
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

local sampleCurrent = 0
local sampleWindow = 8192
local packFormat = ("<i2"):rep(32)
local function doSynth(audioBuffer)
  local buffer = {}
  for note in pairs(held) do
    buffer[#buffer+1] = wavAtHz(wfSine, freq(note), 1,
      sampleCurrent, sampleWindow)
  end
  sampleCurrent = (sampleCurrent + sampleWindow) % SAMPLE_RATE
  if #buffer > 1 then buffer = merge(buffer) elseif #buffer == 1 then buffer = buffer[1] end
  local data = ""
  for i=1, #buffer, 32 do
    data = data .. string.pack(packFormat, table.unpack(buffer, i, i+31))
  end
  audioBuffer:data("mono16", data, SAMPLE_RATE)
end

local source = al.create_source(context)
source:play()

local bufferPool = {al.create_buffer(context)}
local buffersCreated = 1

held[48] = true

while true do
  local buffers = source:get('buffers processed') -- buffersProcessed
  --print('b',buffers,buffersProcessed,source:get('buffers processed'))
  print(buffersCreated)
  if buffers >= buffersCreated then
    bufferPool[#bufferPool+1] = al.create_buffer(context)
    buffersCreated = buffersCreated + 1
  end
  if buffers > 0 then
    local ids = source:unqueue_buffers(buffers)
    --print'yay'
    for i=1, #ids do
      bufferPool[#bufferPool+1] = ids[i]
    end
    --print(#bufferPool)
  end
  for i=1, #bufferPool do
    doSynth(bufferPool[i])
  end
  if #bufferPool > 0 then source:queue_buffers(bufferPool) bufferPool = {} end
  if alsa.inputpending() > 0 then
    local evt = alsa.input()
    if evt[1] == alsa.SND_SEQ_EVENT_NOTEON then
      local pitch = evt[8][2]
      held[pitch] = true

    elseif evt[1] == alsa.SND_SEQ_EVENT_NOTEOFF then
      local pitch = evt[8][2]
      held[pitch] = false
    end
  end
end
