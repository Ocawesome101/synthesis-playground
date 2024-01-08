-- noise related stuff

local snd = require("synth.snd")

local mod = {}

function mod.noiseGenerator()
  local pr, nr
  local li = 0
  return function(i,m)
    if i % m < li then pr = nil nr = nil end
    pr = pr or math.random(snd.SAMPLE_MIN,snd.SAMPLE_MAX)/snd.SAMPLE_MAX
    nr = nr or math.random(snd.SAMPLE_MIN,snd.SAMPLE_MAX)/snd.SAMPLE_MAX
    li = i % m
    return nr
    --return math.max(-1, math.min(1, pr + (pr - nr) * (i/m)))
  end
end

return mod
