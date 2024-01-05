-- basic layout engine since fltk can't do that apparently

local fl = require("moonfltk")

local mod = {MARGIN=5, elements = {}}

local state = {flashers={},inputs={},canvas={},labels={}}
mod.state = state

function mod.init()
  fl.font(fl.COURIER)
  state.window = fl.double_window(10, 10, "Synthesis Playground")
  state.w, state.h = 10, 10
end

local function setDim(self)
  local e = self.flasher
  e:color(self.dim)
  e:labelcolor(self.bright)
  e:damage("user1")
end

local function setBright(self)
  local e = self.flasher
  e:color(self.bright)
  e:labelcolor(self.dim)
  e:damage("user1")
end

-- box with extra flashy bits
function mod.elements.flasher(t)
  local w = fl.width(t.text)
  local dim, bright = (0x444444 & t.color)<<8, (0xCCCCCC & t.color)<<8
  local box = fl.box('up box', 0, 0, w+mod.MARGIN*2, fl.height(), t.text)
  box:color(dim)
  box:labelfont(fl.COURIER)
  box:labelcolor(bright)
  state.flashers[t.text] = {flasher = box, dim = dim, bright = bright, setDim = setDim, setBright = setBright}
  return box
end

function mod.elements.canvas(t)
  local w, h = t.w, t.h
  local box = fl.box_sub('down box', 0, 0, w+mod.MARGIN*2, h+mod.MARGIN*2)
  box:color(0)
  if t.draw then box:override_draw(t.draw) end
  if t.id then state.canvas[t.id] = box end
  return box
end

function mod.elements.button(t)
  local w = fl.width(t.text)
  local but = fl.button(0, 0, w+mod.MARGIN*2, fl.height(), t.text)
  but:labelfont(fl.COURIER)
  if t.callback then
    but:callback(t.callback)
  end
  if t.id then state.inputs[t.id] = but end
  return but
end

function mod.elements.buttonHalf(t)
  local w = fl.width(t.text)
  local but = fl.button(0, 0, w+mod.MARGIN*2, fl.height()/2, t.text)
  but:labelfont(fl.COURIER)
  if t.callback then
    but:callback(t.callback)
  end
  if t.id then state.inputs[t.id] = but end
  return but
end

function mod.elements.menubutton(t)
  local w = fl.width(t.text or "")
  if type(t.widthOverride) == "number" then w = t.widthOverride end
  local mb = fl.menu_button(0, 0, w+mod.MARGIN+20, fl.height(), t.text)
  mb:labelfont(fl.COURIER)
  mb:align('inside')
  for i=1, #t.items do
    mb:add(t.items[i])
  end
  if t.callback then mb:callback(t.callback) end
  if t.id then state.inputs[t.id] = mb end
  return mb
end

function mod.elements.label(t)
  local x, y, w, h = fl.text_extents(t.text)
  local box = fl.box('free boxtype', 0, 0, w+mod.MARGIN*2, fl.height(), t.text)
  box:align(fl.ALIGN_INSIDE | fl.ALIGN_LEFT)
  if t.id then state.labels[t.id] = box end
  return box
end

function mod.elements.number(t)
  local w = fl.width("128") * 2
  local inp = (t.float and fl.float_input or fl.int_input)(0, 0, w, fl.height())
  if t.id then state.inputs[t.id] = inp end
  if t.value then inp:value(t.value) end
  if t.callback then inp:callback(t.callback) end
  return inp
end

local function position(rows, xo, yo, MARGIN)
  if rows.container then rows.container:resize(xo, yo, rows.w+MARGIN*2, rows.h+MARGIN*2) end
  -- position all the elements
  for r, row in ipairs(rows) do
    local lxo = xo
    for c, col in ipairs(row) do
      local resizeW = col:w()
      local lxoa = 0
      if row.wo[c] == "remaining" then
        resizeW = rows.w - row.x[c]
        lxoa = rows.w - (row.x[c + 1] or 0)
        for i=c+1, #row do
          resizeW = resizeW - row[i]:w()
          lxoa = lxoa - row[i]:w()
        end
      end
      col:resize(row.x[c] + lxo + MARGIN, row.y + yo + MARGIN, resizeW, col:h())
      lxo = lxo + lxoa
    end
  end
end

-- a grid is rows and columns of elements.  a 2d table basically.
-- can contain sub-grids.
-- returns width and height of the grid and a table of all the created elements
function mod.elements._grid(grid)
  local rows = {w = 0, h = 0}
  if not grid.nobg then rows.container = fl.box('down box', 0, 0, 1, 1) end

  -- create all the elements
  for r, row in ipairs(grid) do
    local cols = {w = 0, h = 0, x = {}, y = rows.h, wo = {}}
    rows[r] = cols
    for c, col in ipairs(row) do
      if mod.elements[col.type] then
        cols[c] = mod.elements[col.type](col)
        cols.x[c] = cols.w
        cols.w = cols.w + cols[c]:w()
        cols.h = math.max(cols.h, cols[c]:h())
        if col.widthOverride then cols.wo[c] = col.widthOverride end
      end
    end
    rows.h = rows.h + cols.h
    rows.w = math.max(rows.w, cols.w)
  end

  local MARGIN = grid.nobg and 0 or mod.MARGIN

  local ww, wh = state.window:w(), state.window:h()
  state.window:resize(state.window:x(), state.window:y(), math.max(ww, rows.w+MARGIN*2), math.max(wh, rows.h+MARGIN*2))

  position(rows, 0, 0, MARGIN)

  -- needs :x(), :y(), :w(), :h(), and :resize()
  local faux = {}
  local x, y = 0, 0
  function faux:x() return x end
  function faux:y() return y end
  function faux:w() return rows.w + MARGIN*2 end
  function faux:h() return rows.h + MARGIN*2 end
  function faux:resize(x, y, w, h)
    rows.w = w - MARGIN*2
    position(rows, x, y, MARGIN)
  end
  return faux
end

function mod.layout(grid)
  return mod.elements._grid(grid)
end

function mod.present()
  state.window:show()
end

return mod
