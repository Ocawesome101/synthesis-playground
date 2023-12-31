local loops = require("synth.loops")
local time = require("posix.time")

local function sleep_ms(ms)
  time.nanosleep({tv_sec=0,tv_nsec=ms*1000000})
end

loops.startLoop(1)
loops.startNote(1, 1)
sleep_ms(60)
loops.startNote(2, 1)
sleep_ms(60)
loops.endNote(1)
sleep_ms(60)
loops.endNote(2)
sleep_ms(20)
loops.startNote(5, 1)
sleep_ms(80)
local id = loops.endLoop()

loops.playLoop(id)

local thing = 0
repeat
  local frames, timeToNext = loops.nextFrame()
  if #frames > 0 then
    print('p',timeToNext, #frames, frames[1].index, frames[1].max)
  else
    print("P",timeToNext)
  end
  sleep_ms(timeToNext)
  if timeToNext > 75 then
    thing = thing + 1
  end
until timeToNext > 75 and timeToNext < 85 and thing > 2
