-- looper module

local time = require("posix.time")

local mod = {}

local loops = {}

function mod.getTime()
  local spec = time.clock_gettime(time.CLOCK_REALTIME)
  return spec.tv_sec*1000 + spec.tv_nsec/1000000
end

function mod.startLoop(channel)
  loops[#loops+1] = {channel = channel or #loops + 1, playing = false}
  return #loops
end

function mod.startNote(pitch, velocity)
  local loop = loops[#loops]
  local last = loop[#loop]
  if last and not last.duration then
    last.duration = mod.getTime() - last.start
    if last.duration == 0 then loop[#loop] = nil end
  end
  local pitches, velocities = {}, {}
  local current = {pitches=pitches, velocities=velocities, start = mod.getTime()}
  local overwrite
  for i=1, #last.pitches do pitches[i] = last.pitches[i] if pitches[i] == pitch then overwrite = i end end
  for i=1, #last.velocities do velocities[i] = last.velocities[i] end
  if overwrite then
    velocities[overwrite] = velocity
  else
    pitches[#pitches+1] = pitch
    velocites[#velocities+1] = velocity
  end
  loop[#loop+1] = current
end

function mod.endNote(pitch)
  local loop = loops[#loops]
  local last = loop[#loop]
  local pitches, velocities = {}
  local current = {pitches=pitches, velocities=velocities, start = mod.getTime()}
  for i=1, #last.pitches do
    if last.pitches[i] ~= pitch then
      pitches[#pitches+1] = last.pitches[i]
      velocities[#velocities+1] = last.velocities[i]
    end
  end
  if not last.duration then
    last.duration = mod.getTime() - last.start
    if last.duration == 0 then loop[#loop] = nil end
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
    last.duration = mod.getTime() - last.start
    if last.duration == 0 then loop[#loop] = nil end
  end

  return #loops
end

function mod.playLoop(id)
  loops[id].playing = true
  loops[id].startTime = mod.getTime()
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
      local totalTime = 0
      for n=1, index-1 do
        totalTime = totalTime + loop[n].duration
      end
      timeToNext = math.min(timeToNext, mod.getTime() - (loop[index].duration + totalTime))
      if mod.getTime() >= loop[index].duration + totalTime then
        if index == #loop then loop.startTime = mod.getTime() loop.index = 0 end
        loop.index = loop.index + 1
        frames[#frames+1] = loop[index]
      end
    end
  end
  return frames, timeToNext
end

return mod
