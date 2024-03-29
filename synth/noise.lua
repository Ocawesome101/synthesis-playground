-- noise related stuff

local snd = require("synth.snd")

local mod = {}

function mod.noiseGenerator()
  local pr, nr
  local li = 0
  return function(i,m)
    if i % math.max(1,m) < li then pr = nil nr = nil end
    pr = pr or math.random(snd.SAMPLE_MIN,snd.SAMPLE_MAX)/snd.SAMPLE_MAX
    nr = nr or math.random(snd.SAMPLE_MIN,snd.SAMPLE_MAX)/snd.SAMPLE_MAX
    li = i % math.max(1,m)
    return nr
  end
end

return mod
