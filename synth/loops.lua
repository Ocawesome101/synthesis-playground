-- looper module

local util = require("synth.util")

local mod = {}

local loops = {}

function mod.startLoop(channel)
  loops[#loops+1] = {channel = channel or #loops + 1, playing = false}
  return #loops
end

function mod.startNote(pitch, velocity)
  local loop = loops[#loops]
  local last = loop[#loop]
  if last and not last.duration then
    last.duration = util.getTime() - last.start
  end
  local pitches, velocities = {}, {}
  local current = {pitches=pitches, velocities=velocities, start = util.getTime(), channel = loop.channel}
  local overwrite
  if last then
    for i=1, #last.pitches do pitches[i] = last.pitches[i] if pitches[i] == pitch then overwrite = i end end
    for i=1, #last.velocities do velocities[i] = last.velocities[i] end
  end
  if overwrite then
    velocities[overwrite] = velocity
  else
    pitches[#pitches+1] = pitch
    velocities[#velocities+1] = velocity
  end
  loop[#loop+1] = current
end

function mod.endNote(pitch)
  local loop = loops[#loops]
  local last = loop[#loop]
  if not last then return end
  local pitches, velocities = {}, {}
  local current = {pitches=pitches, velocities=velocities, start = util.getTime(), channel = loop.channel}
  for i=1, #last.pitches do
    if last.pitches[i] ~= pitch then
      pitches[#pitches+1] = last.pitches[i]
      velocities[#velocities+1] = last.velocities[i]
    end
  end
  if not last.duration then
    last.duration = util.getTime() - last.start
  end
  loop[#loop+1] = current
end

function mod.endLoop()
  local loop = loops[#loops]
  if #loop <= 1 then -- refuse to loop it
    loops[#loops] = nil
    return false
  end

  local last = loop[#loop]
  if not last.duration then
    last.duration = util.getTime() - last.start
  end

  return #loops
end

function mod.getChannel(id)
  return loops[id].channel
end

function mod.playLoop(id)
  loops[id].playing = true
  loops[id].nextTime = util.getTime()
  loops[id].index = 1
end

function mod.stopLoop(id)
  loops[id].playing = false
end

function mod.nextFrame()
  local frames, timeToNext = {}, math.huge
  for i=1, #loops do
    local loop = loops[i]
    if loop.playing then
      local index = loop.index
      if util.getTime() >= loop.nextTime then
        loop.index = loop.index + 1
        if loop.index > #loop then loop.index = 1 end
        loop.nextTime = util.getTime() + loop[index].duration
        loop[index].index = index
        loop[index].max = #loop
        frames[#frames+1] = loop[index]
      end
      timeToNext = math.min(timeToNext, loop.nextTime - util.getTime())
    end
  end
  return frames, timeToNext
end

return mod
