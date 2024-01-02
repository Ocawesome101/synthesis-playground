-- utility functions

local time = require("posix.time")

local mod = {}

function mod.getTime()
  local spec = time.clock_gettime(time.CLOCK_REALTIME)
  return math.floor(spec.tv_sec*1000 + spec.tv_nsec/1000000)
end

function mod.sleep(ms)
  time.nanosleep({tv_sec=0,tv_nsec=ms*1000000})
end

return mod
