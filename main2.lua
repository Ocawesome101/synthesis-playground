-- main file

local lanes = require("lanes").configure()
local fl = require("moonfltk")

local linda1 = lanes.linda()
local device = (...)

local KEY = "SynthesisPlayground"

local synth_thread = lanes.gen("*", function() 
  local util = require("synth.util")
  local midi = require("synth.midi")

  local PEDAL_SUSTAIN, PEDAL_LOOP = 64, 67

  if device then
    midi.init(device)
  end

  local inLoop = false

  midi.handle("SND_SEQ_EVENT_CONTROLLER", function(e)
    local pedal, pressed = e[8][5], e[8][6]
    if pedal == PEDAL_LOOP then
      inLoop = pressed > 63
      linda1:send(KEY, {"inLoop", inLoop})
    end
  end)

  while true do
    midi.tick()
    util.sleep(10)
  end
end)

local synth = synth_thread()
if synth.status == "error" then
  local _ = synth[1]
  return
end

local MARGIN = 10

local win = fl.double_window(640, 480, "Synthesis Playground")
fl.font(fl.COURIER)

local winw, winh = win:w(), win:h()

local menubar = fl.menu_bar(0, 0, winw, fl.height(), "A")
local _x, _y, _w, _h = fl.text_extents("Loop")
local flasher = fl.box('down box', winw-_w-MARGIN, fl.height(), _w+MARGIN, fl.height(), "Loop")
flasher:color(0x44000000)
flasher:labelcolor(0xCC000000)

menubar:add("File")

flasher:show()

win:done()
win:show()

while fl.wait() do
  if synth.status == "error" then
    local _ = synth[1]
    fl.quit()
    break
  end
  repeat
    local k, v = linda1:receive(0, KEY)
    if k and v[1] == "inLoop" then
      if v[2] then
        flasher:color(fl.rgb_color(0xCC, 0, 0))
        flasher:labelcolor(fl.rgb_color(0x44, 0, 0))
      else
        flasher:color(fl.rgb_color(0x44, 0, 0))
        flasher:labelcolor(fl.rgb_color(0xCC, 0, 0))
      end
    end
  until not k
end
