-- frame module

local gui = require("synth.gui")

local mod = {}

function mod.new(text, x, y, children, w, h)
  local f = {x = x, y = y, w = w, h = h}

  function f.resize(w, h)
  end

  return f
end

return mod
