-- main file

local gui = require("synth.gui")
local button = require("synth.gui.button")
local flasher = require("synth.gui.flasher")
local midi = require("synth.midi")
local util = require("synth.util")

if (...) then
  midi.init(...)
end

gui.init()

local fileMenu, editMenu, loopMenu = {}, {}, {}

local file = button.new("File", 0, 0, fileMenu.show)
local edit = button.new("Edit", file.w+gui.MARGIN, 0, editMenu.show)
local loop = button.new("Loop", edit.x+edit.w+gui.MARGIN, 0, loopMenu.show)

local flasher = flasher.new("Looping", loop.x+loop.w+gui.MARGIN,0)
flasher.x = gui.state.w - flasher.w

while gui.tick() do
  gui.render()
  midi.tick()
  util.sleep(10)
end
