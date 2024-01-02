-- menu thingy
-- really just a list of buttons

local gui = require("synth.gui")
local button = require("synth.gui.button")

local mod = {}

local function null() end

function mod.new(buttons)
  local _callback = null
  local m = {x=0, y=0, w=0, h=0}

  local b = {}
  for i=1, #buttons do
    local bt = buttons[i] 
    b[i] = button.new(bt.text, 0, m.h, bt.callback, true)
    m.w = math.max(b[i].w, m.w)
    m.h = m.h + b[i].h
  end

  for i=1, #buttons do
    b[i].forceSize(m.w, b[i].h)
  end

  local surf = gui.getSurface(m.w, m.h)
  surf:fillRect(nil, gui.COLOR_BG_MENU)
  local tex = gui.state.rdr:createTextureFromSurface(surf)

  function m.setParent(e)
    for i=1, #b do
      b[i].x, b[i].y = m.x, b[i].y + e.y + e.h + gui.MARGIN
    end
    m.x, m.y = e.x, e.y+e.h+gui.MARGIN
  end

  local show = false
  local hideNextRender = false
  function m.render(s)
    if show then
      s.rdr:copy(tex, nil, {x=m.x, y=m.y, w=m.w, h=m.h})
    end
    if hideNextRender then
      hideNextRender = false
      show = false
      for i=1, #b do
        gui.removeElement(b[i])
        gui.removeElement(m)
      end
    end
  end

  function m.unclick()
  end

  function m.hover()
  end

  function m.unfocus()
    hideNextRender = true
  end

  function m.toggle()
    if show then
      hideNextRender = true
      show = false
    else
      show = true
      gui.addElement(m)
      for i=1, #b do
        gui.addElement(b[i])
      end
    end
  end

  return m
end

return mod
