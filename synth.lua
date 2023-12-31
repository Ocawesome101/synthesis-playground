-- lua version
-- uses moonal and midialsa

local alsa = require("midialsa")
local al = require("moonal")
local A4=440

alsa.start()
local _ = alsa.client("LuaSynthesizer", 1, 1, true)
assert(alsa.connectfrom(0, alsa.parse_address(assert(..., "need midi device"))), "invalid midi device")

local held = {}

local wave = {}
local generate = false

if arg[2] == "gen" then
  generate = true
  wave = arg[3] or "sine"
else
  for line in io.lines("waves/"..(arg[2] or "sine")..".txt") do
    wave[#wave+1] = tonumber(line)
  end
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
    local amp = SAMPLE_MAX
    return 4*amp/max * math.abs((((cur-max/4)%max)+max)%max - max/2) - amp
  end,
}

generators.fancy = function(cur, max)
    return math.max(generators.sine(cur, max), generators.saw(cur, max))
end

local function genWavHz(generator, hz, amp, count)
  local buffer = {}

  local samples = SAMPLE_RATE/hz
  for d=0, count-1 do
    for i=0, samples do
      buffer[i+d*samples+1] = math.floor(generator(i, samples) * amp + 0.5)
    end
  end

  return buffer
end

local function getPCM(hz, amp, duration)
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
local velocities = {}

local function doSynth()
  local sourceIndex = 0
  for _, _note in pairs(held) do
    sourceIndex = sourceIndex + 1
    local note = _note[1]
    local velocity = _note[2]
    if notes[sourceIndex] ~= note or velocities[sourceIndex] ~= velocity then
      notes[sourceIndex] = note
      velocities[sourceIndex] = velocity
      local source, buffer = sources[sourceIndex], buffers[sourceIndex]
      if sources[sourceIndex] then
        source:stop()
        source:delete()
      end
      source = al.create_source(context)
      sources[sourceIndex] = source
      source:set("looping", true)

      buffer = al.create_buffer(context)
      buffers[sourceIndex] = buffer
      buffer:data('mono16', getPCM(freq(note), _note[2], 1), SAMPLE_RATE)
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

local sustain
local function addHeld(pitch, velocity)
  for i=1, #held do
    if held[i][1] == pitch then held[i][2] = velocity/128 held[i][4] = false return end
  end
  held[#held+1] = {pitch, velocity/128, sustain}
end

local function removeHeld(pitch)
  for i=1, #held do
    if held[i][1] == pitch then
      held[i][4] = true
      if not held[i][3] then table.remove(held, i) end
      return
    end
  end
end

while true do
  doSynth()
  local evt = alsa.input()
  if evt[1] == alsa.SND_SEQ_EVENT_NOTEON then
    local pitch = evt[8][2]
    addHeld(pitch, evt[8][3])

  elseif evt[1] == alsa.SND_SEQ_EVENT_NOTEOFF then
    local pitch = evt[8][2]
    removeHeld(pitch)
  elseif evt[1] == alsa.SND_SEQ_EVENT_CONTROLLER then
    if evt[8][6] > 63 then
      sustain = true
      for i=1, #held do
        held[i][3] = true
      end
    else
      sustain = false
      local ioff = 0
      for i=1, #held do
        i = i + ioff
        if held[i] then
          held[i][3] = false
          if held[i][4] then
            ioff = ioff - 1
            table.remove(held, i)
          end
        end
      end
    end
  end
end
