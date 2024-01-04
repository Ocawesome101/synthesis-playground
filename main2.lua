-- main file

local lanes = require("lanes").configure()
local fl = require("moonfltk")
local layout = require("synth.layout")
local waves = require("synth.waves")

local linda1 = lanes.linda()
local device = (...)

local KEY_FROMSYNTH = "SynthSend"
local KEY_TOSYNTH = "SynthRecv"

local synth_thread = lanes.gen("*", function() 
  local util = require("synth.util")
  local midi = require("synth.midi")
  local loop = require("synth.loops")
  local snd = require("synth.snd")
  snd.init()

  local PEDAL_SUSTAIN, PEDAL_LOOP = 64, 67

  if device then
    midi.init(device)
  end

  local inLoop = false
  local channel = 0
  local custom = {}
  local wave = {[0] = waves.generators.sine}
  local sample = ""
  local samples = {}
  local held = {[0] = {}}

  midi.handle("SND_SEQ_EVENT_CONTROLLER", function(e)
    local pedal, pressed = e[8][5], e[8][6]
    if pedal == PEDAL_LOOP then
      inLoop = pressed > 63
      if inLoop then
        loop.startLoop()
      else
        local id = loop.endLoop()
      end
      linda1:send(KEY_FROMSYNTH, {"inLoop", inLoop})
    end
  end)

  local function begin(pitch, velocity)
    local amp = velocity/128

    snd.startLoop(pitch, velocity, waves.getPCMString(waves.generatePCM(wave[channel], snd.freq(pitch), amp)), channel)
  end

  midi.handle("SND_SEQ_EVENT_NOTEON", function(evt)
    local pitch = evt[8][2]
    local velocity = evt[8][3]
    held[channel][pitch] = velocity

    begin(pitch, velocity)
    if inLoop then
      loop.startNote(pitch, velocity)
    end
  end)

  midi.handle("SND_SEQ_EVENT_NOTEOFF", function(evt)
    local pitch = evt[8][2]
    held[channel][pitch] = false

    if not sustain then
      snd.stopLoop(pitch, channel)
      if inLoop then
        loop.endNote(pitch)
      end
    end
  end)

  while true do
    midi.tick()
    repeat
      local k, v = linda1:receive(0, KEY_TOSYNTH)
      if k and v[1] == "channel" then
        print("change channel: " .. v[2])
        channel = v[2]
        if not held[channel] then held[channel] = {} end
      elseif k and v[1] == "wave" then
        print("change wave: " .. v[2])
        wave[channel] = waves.generators[v[2]] or custom[v[2]] or function() end
      elseif k and v[1] == "custom" then
        print("update custom wave: " .. v[2])
        custom[v[2]] = v[3]
      elseif k and samples[sample] and v[1] == "addsample" then
        print("add sample PCM")
        samples[sample][v[2]] = v[3]
      elseif k and v[1] == "sample" then
        print("change sample set: " .. v[2])
        sample = v[2]
        samples[sample] = samples[sample] or {}
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

local function buildWave(custom)
  return function(cur, max)
    local fvalues = {}
    for l, layer in ipairs(custom) do
      local lvalues = {}
      for i=1, #layer do
        local gen = waves.generators[layer[i].wave]
        if layer[i].shift then gen = waves.phaseshift(gen, layer[i].shift) end
        values[i] = gen(cur, max)
      end
      if layer.method == "abs" then
        fvalues[l] = waves.abs(lvalues)
      elseif layer.method == "avg" then
        fvalues[l] = waves.avg(lvalues)
      end
    end
    if custom.method == "abs" then
      return waves.abs(fvalues)
    elseif custom.method == "avg" then
      return waves.avg(fvalues)
    end
  end
end

local function synthCh()
  linda1:send(KEY_TOSYNTH, {"channel", tonumber(layout.state.inputs.channel:value()) or 0})
end

local mainControls =  { type = "_grid", nobg=true, {
  {type="button",text="Save"},{type="button",text="Load"},{type="button",text="New"},
  {type="flasher",text="Loop",color=0xFF0000,align=-1} }, }

local current_wave = waves.generators.sine
local customWaves = {}
local function waveSelect(mb)
  layout.state.inputs.waveMenu:value(mb:value())
  layout.state.inputs.waveMenu:label(mb:value())
  layout.state.inputs.synthWaveMenu:value(mb:value())
  layout.state.inputs.synthWaveMenu:label(mb:value())

  current_wave = waves.generators[mb:value()] or buildWave(customWaves[mb:value()])
  layout.state.canvas.wavePreview:damage("user1")
  linda1:send(KEY_TOSYNTH, {"wave", mb:value()})
end

local function labeledIntField(name, id, callSet)
  local function callUp()
    local i = layout.state.inputs[id]
    i:value((tonumber(i:value()) or 0) + 1)
    callSet()
  end
  local function callDown()
    local i = layout.state.inputs[id]
    i:value(math.max(0, (tonumber(i:value()) or 0) - 1))
    callSet()
  end

  return
    {type="label",text=name},{type="number",id=id,callback=callSet,value="0"},
    {type="_grid",nobg=true,{{type="buttonHalf",text="+",callback=callUp}},{{type="buttonHalf",text="-",callback=callDown}}}
end

local synthControls = { type = "_grid",
  { -- row 1: channel
    labeledIntField("Channel:", "channel", synthCh) },
  { -- row 2: wave
    {type="label",text="Wave:"},
    {type="menubutton", text="sine", items={}, callback=waveSelect, widthOverride = "remaining", id="synthWaveMenu"}
  }
}

local function canvasDraw(self)
  self:super_draw()
  local x, y, w, h = self:xywh()
  fl.color(0x44FF4400)
  for step=1, 64 do
    fl.point(x+step+layout.MARGIN, y+32+layout.MARGIN+math.floor(current_wave(step, 64)*-32))
  end
end

local custom = 0
local function addWave()
  custom = custom + 1
  local name = "custom"..custom
  customWaves[name] = { method = "abs", { method = "abs", { wave = "sine" } } }
  layout.state.inputs.synthWaveMenu:add(name)
  layout.state.inputs.waveMenu:add(name)
end

local waveControlsExtra = { type = "_grid",
  { labeledIntField("Layer", "waveIndex", function() end) },
  { labeledIntField("Wave", "waveIndex", function() end) },
  { {type = "label", text = "Generator"},
    {type = "menubutton", items={}, widthOverride = 64, text = "sine", callback=waveEditSelect, id="waveEditMenu"} },
  { {type = "label", text="Combine"},
    {type = "menubutton", items={"abs", "avg"}, widthOverride=32, text="abs", callback=waveEditMode, id="waveEditMode"} },
  { {type = "label", text="Phase"},
    {type="number", float = true} },
}

local waveControls = { type = "_grid",
  { {type="menubutton", items={}, widthOverride = 64, text = "sine", callback=waveSelect, id="waveMenu"},
    {type="button", text="+", callback=addWave}},
  { { type = "canvas", w = 64, h = 64, draw = canvasDraw, id = "wavePreview" }, waveControlsExtra }
}

local uiGrid = {
  type = "_grid",
  { mainControls },
  { synthControls, waveControls },
}

layout.init()
layout.layout(uiGrid)
layout.present()

do
  local _waves = {}
  for wave, _ in pairs(waves.generators) do
    _waves[#_waves+1] = wave
  end
  table.sort(_waves)
  for i=1, #_waves do
    layout.state.inputs.synthWaveMenu:add(_waves[i])
    layout.state.inputs.waveMenu:add(_waves[i])
  end
end

fl.set_timeout(0.05, true, function() end)

while fl.wait() do
  if synth.status == "error" then
    local _ = synth[1]
    fl.quit()
    break
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
