-- main file

local gui = require("synth.gui")
local button = require("synth.gui.button")
local flasher = require("synth.gui.flasher")
local menubar = require("synth.gui.menubar")
local midi = require("synth.midi")
local util = require("synth.util")

if (...) then
  midi.init(...)
end

gui.init()

local menuBar = menubar.new(0, 0, {
  {text = "File", menu = {
    {text = "Create New"},
    {text = "Open"},
    {text = "Save"},
    {text = "Save As"},
    {text = "Quit", callback = gui.exit}
  }},
})

local flasher = flasher.new("Looping", 0,0)
flasher.x = gui.state.w - flasher.w

while gui.tick() do
  gui.render()
  midi.tick()
  util.sleep(10)
end
