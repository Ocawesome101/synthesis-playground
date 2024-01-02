-- menu bar!

local gui = require("synth.gui")
local button = require("synth.gui.button")
local menu = require("synth.gui.menu")

local mod = {}

function mod.new(x, y, buttons)
  local created = {}
  local menus = {}
  for i=1, #buttons do
    local b = buttons[i]
    local l = created[i-1]
    local _callback
    created[i] = button.new(
      b.text, l and (l.w+l.x+gui.MARGIN) or x, y,
      b.callback or (function() if _callback then _callback() end end))
    if b.menu then
      menus[i] = menu.new(b.menu)
      _callback = menus[i].toggle
      menus[i].setParent(created[i])
    end
  end
  return created
end

return mod
