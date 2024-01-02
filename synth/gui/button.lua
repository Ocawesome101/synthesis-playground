-- gui buttons

local sdl = require("SDL")
local gui = require("synth.gui")

local mod = {}

function mod.new(text, x, y, callback)
  local w, h = gui.state.font:sizeUtf8(text)
  local bw, bh = w+gui.MARGIN*2, h+gui.MARGIN*2

  local states = {}
  local surf = gui.getSurface(bw, bh)
  local ts

  -- state 'idle'
  surf:fillRect(nil, gui.COLOR_BG_BUTTON_IDLE)
  ts = gui.state.font:renderUtf8(text, "shaded",
    gui.COLOR_FG_BUTTON_IDLE, gui.COLOR_BG_BUTTON_IDLE)
  ts:blit(surf, nil, {x=gui.MARGIN, y=gui.MARGIN, w=w, h=h})

  states.idle = gui.state.rdr:createTextureFromSurface(surf)
  
  -- state 'hover'
  surf:fillRect(nil, gui.COLOR_BG_BUTTON_HOVER)
  ts = gui.state.font:renderUtf8(text, "shaded",
    gui.COLOR_FG_BUTTON_HOVER, gui.COLOR_BG_BUTTON_HOVER)
  ts:blit(surf, nil, {x=gui.MARGIN, y=gui.MARGIN, w=w, h=h})
  states.hover = gui.state.rdr:createTextureFromSurface(surf)

  -- state 'press'
  surf:fillRect(nil, gui.COLOR_BG_BUTTON_PRESS)
  ts = gui.state.font:renderUtf8(text, "shaded",
    gui.COLOR_FG_BUTTON_PRESS, gui.COLOR_BG_BUTTON_PRESS)
  ts:blit(surf, nil, {x=gui.MARGIN, y=gui.MARGIN, w=w, h=h})
  states.press = gui.state.rdr:createTextureFromSurface(surf)

  local state = "idle"

  local b = {w = bw, h = bh, x = x, y = y}
  gui.addElement(b)

  function b.render(s)
    s.rdr:copy(states[state], nil, {x=b.x, y=b.y, w=bw, h=bh})
  end

  function b.click(button)
    if button == sdl.mouseButton.Left then
      state = "press"
      if callback then callback() end
    end
  end

  function b.unclick()
    state = "hover"
  end

  function b.hover()
    if state ~= "press" then
      state = "hover"
    end
  end

  function b.unhover()
    state = "idle"
  end

  return b
end

return mod
