-- main file

local lanes = require("lanes").configure()
local fl = require("moonfltk")

local linda1 = lanes.linda()
local device = (...)

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
      linda1:send("set", "inLoop", inLoop)
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

local win = fl.double_window(640, 480, "Synthesis Playground")
win:done()
win:show()
fl.run()
