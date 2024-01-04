-- main file

local lanes = require("lanes").configure()
local fl = require("moonfltk")
local layout = require("synth.layout")

local linda1 = lanes.linda()
local device = (...)

local KEY_FROMSYNTH = "SynthSend"
local KEY_TOSYNTH = "SynthRecv"

local synth_thread = lanes.gen("*", function() 
  local util = require("synth.util")
  local midi = require("synth.midi")
  local loop = require("synth.loops")

  local PEDAL_SUSTAIN, PEDAL_LOOP = 64, 67

  if device then
    midi.init(device)
  end

  local inLoop = false

  midi.handle("SND_SEQ_EVENT_CONTROLLER", function(e)
    local pedal, pressed = e[8][5], e[8][6]
    if pedal == PEDAL_LOOP then
      inLoop = pressed > 63
      linda1:send(KEY_FROMSYNTH, {"inLoop", inLoop})
    end
  end)

  local channel = 0
  while true do
    midi.tick()
    repeat
      local k, v = linda1:receive(0, KEY_TOSYNTH)
      if k and v[1] == "channel" then
        print("change channel: " .. v[2])
        channel = v[2]
      end
    until not k
    util.sleep(10)
  end
end)

local synth = synth_thread()
if synth.status == "error" then
  local _ = synth[1]
  return
end

--[[
local MARGIN = 10

local _, _, sw, sh = fl.screen_xywh(1)

fl.font(fl.COURIER)

local win = fl.double_window(sw, sh, "Synthesis Playground")
win:fullscreen()

local winw, winh = win:w(), win:h()
local extraw = 0

local flashers = {}

local function makeFlasher(text, color, x, y)
  local dim, bright = (0x444444 & color)<<8, (0xCCCCCC & color)<<8 
  local _x, _y, _w, _h = fl.text_extents(text)
  if x < 0 then x = winw + x - _w - MARGIN end
  if y < 0 then y = winh + y end

  local flasher = fl.box('up box', x, y, _w+MARGIN, fl.height(), text)
  flashers[flasher] = {dim = dim, bright = bright}
  flasher:color(dim)
  flasher:labelcolor(bright)
  flasher:labelfont(fl.COURIER)

  flasher:show()

  return flasher
end

local function setBright(f)
  f:color(flashers[f].bright)
  f:labelcolor(flashers[f].dim)
  flasher:damage('user2')
end

local function setDim(f)
  f:color(flashers[f].dim)
  f:labelcolor(flashers[f].bright)
  flasher:damage('user2')
end

local function text_width(text)
  local _x, _y, _w, _h = fl.text_extents(text)
  return _w
end

local flasherLoop = makeFlasher("Loop", 0xFF0000, -1, 0)
extraw = extraw + flasherLoop:w()

local flasherPlay = makeFlasher("Play", 0x00FF00, -extraw, 0)
extraw = extraw + flasherPlay:w()

--== MENU BAR ==--
local menubar = fl.menu_bar(0, 0, winw-extraw, fl.height())
menubar:textfont(fl.COURIER)
menubar:add("File")

local frameMain = fl.group(0, fl.height()+1, winw, winh-fl.height())
frameMain:box('up box')

--== SYNTH FRAME ==--
local tabSynth = fl.group(0, fl.height()+1,
  winw/2, (winh-fl.height())/2)
tabSynth:box('down box')

local labelSynth = fl.box(0, fl.height()+1, winw/2, fl.height(), "Synth")
labelSynth:labelfont(fl.COURIER)
labelSynth:box('up box')

-- prevent resize keys - interface is small
local inChannelGroup = fl.group(
  text_width("Channel: ")+MARGIN, fl.height()*2,
  40+fl.height()*2+MARGIN*2, fl.height()+MARGIN*2)

local changeChannel
local inChannel = fl.int_input(
  inChannelGroup:x() + MARGIN, inChannelGroup:y()+MARGIN,
  40, fl.height(), "Channel: ")
inChannel:value("0")
inChannel:callback(function()
  if tonumber(inChannel:value()) then changeChannel = true end
end)
inChannel:labelfont(fl.COURIER)

local inChannelUp = fl.button(
  inChannel:w() + inChannel:x(), inChannel:y(),
  inChannel:h(), inChannel:h(), "+")
inChannelUp:callback(function()
  inChannel:value((tonumber(inChannel:value()) or 0) + 1)
  changeChannel = true
end)

local inChannelDown = fl.button(
  inChannel:w() + inChannel:x()+inChannel:h(), inChannel:y(),
  inChannel:h(), inChannel:h(), "-")
inChannelDown:callback(function()
  inChannel:value(math.max(0, (tonumber(inChannel:value()) or 0) - 1))
  changeChannel = true
end)

inChannelGroup:done()

local inVoiceGroup = fl.group(
  inChannelGroup:x() + inChannelGroup:w(), inChannelGroup:y(),
  text_width("########")+MARGIN*2, fl.height()+MARGIN*2
)
inVoiceGroup:done()

tabSynth:done()

--== WAVE FRAME ==--
local tabWave = fl.group(0, tabSynth:y()+tabSynth:h(),
  winw/2, (winh-fl.height())/2)
tabWave:box('down box')
local labelWave = fl.box(0, fl.height()+1, winw/2, fl.height(), "Wave")
labelWave:labelfont(fl.COURIER)
labelWave:box('up box')

tabWave:done()

--== LOOP FRAME ==--
local tabLoops = fl.group(winw/2, fl.height()+1,
  winw/2, winh-fl.height())
tabLoops:box('down box')

local labelLoop = fl.box(0, fl.height()+1, winw/2, fl.height(), "Loop")
labelLoop:labelfont(fl.COURIER)
labelLoop:box('up box')

tabLoops:done()

frameMain:done()
frameMain:show()

win:done()
win:show()]]

local uiGrid = {
  type = "_grid",
  {
    {type="button",text="Save"},{type="button",text="Load"},{type="button",text="New"},
    {type="flasher",text="Loop",color=0xFF0000,align=-1} },
  {
    {type="label",text="Ch"},{type="number",id="channel"},
      {type="_grid",nobg=true,{{type="buttonHalf",text="+"}},{{type="buttonHalf",text="-"}}}}
}

layout.init()
local grid = layout.layout(uiGrid)
layout.present()

fl.set_timeout(0.05, true, function() end)

while fl.wait() do
  if synth.status == "error" then
    local _ = synth[1]
    fl.quit()
    break
  end
  if changeChannel then
    changeChannel = false
    linda1:send(KEY_TOSYNTH, {"channel", tonumber(inChannel:value()) or 0})
  end
  repeat
    local k, v = linda1:receive(0, KEY_FROMSYNTH)
    if k and v[1] == "inLoop" then
      if v[2] then
        layout.state.flashers.Loop:setBright()
      else
        layout.state.flashers.Loop:setDim()
      end
    end
  until not k
end
