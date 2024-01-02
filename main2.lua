-- main file

local lanes = require("lanes").configure()
local fl = require("moonfltk")

local linda1 = lanes.linda()
local device = (...)

local synth_thread = lanes.gen("*", function() 
  local util = require("synth.util")
  local midi = require("synth.midi")

  if device then
    midi.init(device)
  end

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
