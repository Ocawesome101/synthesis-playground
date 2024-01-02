-- gui futtons

local sdl = require("SDL")
local gui = require("synth.gui")

local mod = {}

function mod.new(text, x, y)
  local w, h = gui.state.font:sizeUtf8(text)
  local fw, fh = w+gui.MARGIN*2, h+gui.MARGIN*2

  local states = {}
  local surf = gui.getSurface(fw, fh)
  local ts

  -- state 'off'
  surf:fillRect(nil, gui.COLOR_BG_FLASHER_OFF)
  ts = gui.state.font:renderUtf8(text, "blended",
    gui.COLOR_FG_FLASHER_OFF)
  ts:blit(surf, nil, {x=gui.MARGIN, y=gui.MARGIN, w=w, h=h})
  states.off = gui.state.rdr:createTextureFromSurface(surf)
  
  -- state 'on'
  surf:fillRect(nil, gui.COLOR_BG_FLASHER_ON)
  ts = gui.state.font:renderUtf8(text, "blended",
    gui.COLOR_FG_FLASHER_ON)
  ts:blit(surf, nil, {x=gui.MARGIN, y=gui.MARGIN, w=w, h=h})
  states.on = gui.state.rdr:createTextureFromSurface(surf)

  local state = "off"

  local f = {w = fw, h = fh, x = x, y = y}
  gui.addElement(f)

  function f.render(s)
    s.rdr:copy(states[state], nil, {x=f.x, y=f.y, w=fw, h=fh})
  end

  function f.on()
    state = "on"
  end

  function f.off()
    state = "off"
  end

  return f
end

return mod
