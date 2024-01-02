local sdl = require("SDL")
local ttf = require("SDL.ttf")

local SCALE_FACTOR = 1

local mod = {
  SCALE_FACTOR = SCALE_FACTOR,
  FONT_SIZE = 12 * SCALE_FACTOR,
  FONT_FILE = "/usr/share/fonts/TTF/Hack-Regular.ttf",

  MARGIN = 4 * SCALE_FACTOR,

  COLOR_BG_MAIN = 0x656565,
  COLOR_BG_BUTTON_IDLE = 0x888888,
  COLOR_BG_BUTTON_HOVER = 0x999999,
  COLOR_BG_BUTTON_PRESS = 0x444444,

  COLOR_FG_BUTTON_IDLE = 0xEEEEEE,
  COLOR_FG_BUTTON_HOVER = 0xEEEEEE,
  COLOR_FG_BUTTON_PRESS = 0xEEEEEE,

  COLOR_BG_FLASHER_ON = 0xCC0000,
  COLOR_BG_FLASHER_OFF = 0x440000,

  COLOR_FG_FLASHER_ON = 0x440000,
  COLOR_FG_FLASHER_OFF = 0xCC0000,
}

mod.elements = {}

-- win, rdr, font, w, h
local state = {}
local init

mod.state = state

function mod.init()
  if init then return end
  assert(sdl.init {
    sdl.flags.Video,
    sdl.flags.Events
  })

  assert(ttf.init())

  local dmode = assert(sdl.getDesktopDisplayMode(0))
  state.w, state.h = dmode.w, dmode.h

  state.win = sdl.createWindow {
    width = state.w, height = state.h,
    x = 0, y = 0,
    title = "Synthesis Playground",
    flags = {
      sdl.window.Borderless,
      sdl.window.Desktop
    }
  }

  state.font = ttf.open(mod.FONT_FILE, mod.FONT_SIZE)
  state.rdr = sdl.createRenderer(state.win, 0, {sdl.rendererFlags.PresentVSYNC})

  state.rdr:setDrawColor(mod.COLOR_BG_MAIN)

  init = true
end

function mod.addElement(el)
  mod.elements[#mod.elements+1] = el
end

function mod.removeElement(el)
  for i=#mod.elements, 1, -1 do
    if mod.elements[i] == el then
      table.remove(mod.elements, i)
    end
  end
end

-- i don't know WHY
-- i don't know HOW
-- but only when i switch it to BGR24 does it work right
function mod.getSurface(w, h)
  return sdl.createRGBSurface(w, h, 24):convertFormat(sdl.pixelFormat.BGR24)
end

function mod.render()
  state.rdr:clear()

  for i=1, #mod.elements do
    local el = mod.elements[i]
    if not el then break end
    el.render(state)
  end

  state.rdr:present()
end

local exit = false

function mod.exit()
  exit = true
end

local function findElement(x, y, un)
  for i=1, #mod.elements do
    local el = mod.elements[i]
    if x>=el.x and y>=el.y and x<el.x+el.w and y<el.y+el.h and el.click then
      return el
    elseif un == 1 and el.unhover then
      el.unhover()
    elseif un == 2 and el.unfocus then
      el.unfocus()
    end
  end
end

function mod.tick()
  for e in sdl.pollEvent() do
    if exit or e.type == sdl.event.Quit then
      return false

    elseif e.type == sdl.event.MouseButtonDown then
      local el = findElement(e.x, e.y)
      if el then el.click(e.button, e.x - el.x + 1, e.y - el.y + 1) end

    elseif e.type == sdl.event.MouseButtonUp then
      local el = findElement(e.x, e.y, 2)
      if el then el.unclick(e.button, e.x - el.x + 1, e.y - el.y + 1) end
      
    elseif e.type == sdl.event.MouseMotion then
      local el = findElement(e.x, e.y, 1)
      if el then el.hover(e.button, e.x - el.x + 1, e.y - el.y + 1) end
    end
  end

  for i=#mod.elements, 1, -1 do
    if mod.elements[i].destroy then
      table.remove(mod.elements, i)
    end
  end

  return true
end

return mod
