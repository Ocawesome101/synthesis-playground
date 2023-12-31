local al = require("moonal")

local mod = {}

local A4=440

mod.SAMPLE_MIN = -32768
mod.SAMPLE_MAX = 32767
mod.SAMPLE_RATE = 48000

-- MIDI note to frequency
function mod.freq(note)
  return A4 * 2^((note-69)/12)
end

local device = al.open_device()
local context = al.create_context(device)

-- table of:
-- {
--   source = moonal_source,
--   buffer = moonal_buffer,
--   note = number,
--   velocity = number,
--   voice = number,
--   loop = boolean,
--   active = boolean,
--   available = boolean
-- }
local sources = {}

function mod.checkSourceBuffers()
  for i=1, #sources do
    local s = sources[i]
    if (not s.active or not s.loop) and (not s.available) then
      local buf = s.source:unqueue_buffers(1)
      if buf then
        s.buffer:destroy()
        s.source:stop()
        s.available = true
      end
    end
  end
end

local function stopSource(s)
  s.source:set("looping", false)
  s.active = false
  s.available = false
end

local function writeSource(s, note, velocity, pcm, channel, loop)
  s.note = note
  s.velocity = velocity
  s.channel = channel
  s.loop = not not loop

  s.buffer = al.create_buffer(context)
  s.buffer:data('mono16', pcm, mod.SAMPLE_RATE)
  s.source:queue_buffers({s.buffer})
  s.source:set("looping", not not loop)
  s.source:play()
  s.active = true
  s.available = false
end

local function newSource(note, velocity, pcm, channel, loop)
  local s = {
    source = al.create_source(context)
  }
  writeSource(s, note, velocity, pcm, channel, loop)
  return s
end

function mod.startLoop(note, velocity, pcm, channel)
  channel = channel or 0
  velocity = velocity or 64
  return mod.addNote(note, velocity, pcm, channel, true)
end

function mod.stopLoop(note, channel)
  for i=#sources, 1, -1 do
    local s = sources[i]
    if s.note == note and s.channel == channel or channel == -1 then
      stopSource(s)
    end
  end
end

function mod.addNote(note, velocity, pcm, channel, loop)
  mod.checkSourceBuffers()
  channel = channel or 0
  for i=1, #sources do
    local s = sources[i]
    if s.note == note and s.channel == channel then
      if s.velocity == velocity then
        return true
      elseif s.available then
        return writeSource(s, note, velocity, pcm, channel, loop)
      else
        stopSource(s)
      end
    end
  end
  sources[#sources+1] = newSource(note, velocity, pcm, channel, loop)
end

return mod
