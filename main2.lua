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
        lvalues[i] = gen(cur, max) * (layer[i].amp or 1)
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
  {type="flasher",text="Loop",color=0xFF0000} }, }

local current_wave = waves.generators.sine
local currentCustom
local customWaves = {}

local function waveSelectSynth(mb)
  local value
  if type(mb) == "string" then value = mb else value = mb:value() end
  layout.state.inputs.synthWaveMenu:value(value)
  layout.state.inputs.synthWaveMenu:label(value)
  if customWaves[value] then
    linda1:send(KEY_TOSYNTH, {"custom", value, buildWave(customWaves[value])})
  end
  linda1:send(KEY_TOSYNTH, {"wave", value})
end

local function upDownButtons(id, up, down)
  return {type="_grid",nobg=true,
    {{type="buttonHalf",text="+",callback=up,id=id.."Up"}},
    {{type="buttonHalf",text="-",callback=down,id=id.."Down"}}}
end

local function labeledNumberField(name, id, callSet, float, min, max)
  local inc = float and 0.1 or 1
  min = min or -math.huge
  max = max or math.huge
  local function callUp()
    local i = layout.state.inputs[id]
    i:value(math.max(min, math.min(max, (tonumber(i:value()) or 0) + inc)))
    callSet(i)
  end
  local function callDown()
    local i = layout.state.inputs[id]
    i:value(math.max(min, math.min(max, (tonumber(i:value()) or 0) - inc)))
    callSet(i)
  end

  return
    {type="label",text=name},{type="number",float=float,id=id,callback=callSet,value="0",text="0"},
    upDownButtons(id, callUp, callDown)
end

local synthControls = { type = "_grid",
  { -- row 1: channel
    labeledNumberField("Channel:", "channel", synthCh, nil, 0) },
  { -- row 2: wave
    {type="label",text="Wave:"},
    {type="menubutton", text="sine", items={}, callback=waveSelectSynth, widthOverride = "remaining", id="synthWaveMenu"}
  }
}

local function canvasDraw(self)
  if not self then return end
  self:super_draw()
  local x, y, w, h = self:xywh()
  fl.color(0x44FF4400)
  for step=1, 64 do
    fl.point(x+step+layout.MARGIN, y+32+layout.MARGIN+math.floor(current_wave(step, 64)*-32))
  end
end

local function customWaveSet(mb)
  if not currentCustom then return end

  if mb and mb:label() then mb:label(mb:value()) end
  local inputs = layout.state.inputs
  local ilayer = tonumber(inputs.waveLayerIndex:value())
  local iwave = tonumber(inputs.waveIndex:value())
  local waveid = inputs.waveEditMenu:value()
  local mode = inputs.waveEditMode:value()
  local mainMode = inputs.waveMainMode:value()
  local phase = tonumber(inputs.wavePhase:value())
  local amp = tonumber(inputs.waveAmp:value()) or 1

  currentCustom.method = mainMode

  currentCustom[ilayer] = currentCustom[ilayer] or {method = "abs"}
  local layer = currentCustom[ilayer]
  if mb ~= inputs.waveLayerIndex then
    layer.method = mode
    layer[iwave] = layer[iwave] or {}
    local wave = layer[iwave]
    if mb ~= inputs.waveIndex then
      wave.wave = waveid
      wave.shift = phase
      wave.amp = amp or 1
    else
      wave.wave = wave.wave or waveid
      waveid = wave.wave
      phase = wave.shift or 0
      amp = wave.amp or 1
    end
  else
    currentCustom[ilayer][1] = {wave = "sine", shift = 0, amp = 1}
    waveid = "sine"
    phase = 0
    amp = 1
    iwave = 1
  end

  for i=#currentCustom, 1, -1 do
    for j=#currentCustom[i], 1, -1 do
      if currentCustom[i][j].wave == "none" then
        table.remove(currentCustom[i], j)
      end
    end

    if #currentCustom[i] == 0 then
      if #currentCustom > 1 then
        table.remove(currentCustom, i)
      else
        currentCustom[1][1] = {wave = "sine"}
      end
    end
  end
  ilayer = math.min(ilayer, #currentCustom)
  iwave = math.min(iwave, #currentCustom[ilayer])

  local rmode = currentCustom[ilayer].method
  local rwaveid = currentCustom[ilayer][iwave].wave
  local rphase = currentCustom[ilayer][iwave].shift or 0
  local ramp = currentCustom[ilayer][iwave].amp or 1

  inputs.waveLayerIndex:value(ilayer)
  inputs.waveIndex:value(iwave)

  inputs.waveEditMenu:value(rwaveid)
  inputs.waveEditMenu:label(rwaveid)

  inputs.waveEditMode:value(rmode)
  inputs.waveEditMode:label(rmode)

  inputs.wavePhase:value(rphase)
  inputs.waveAmp:value(ramp)

  current_wave = buildWave(currentCustom)
  layout.state.canvas.wavePreview:damage("user1")
end

local custom = 0
local waveControlsExtra = { type = "_grid",
  { {type = "label", text="Main Combinator"},
    {type = "menubutton", items={"abs", "avg"}, widthOverride=32, text="abs", callback=customWaveSet, id="waveMainMode"} },
  { labeledNumberField("Layer", "waveLayerIndex", customWaveSet, nil, 1) },
  { labeledNumberField("Wave", "waveIndex", customWaveSet, nil, 1) },
  { {type = "label", text = "Generator"},
    {type = "menubutton", items={}, widthOverride = 64, text = "sine", callback=customWaveSet, id="waveEditMenu"} },
  { {type = "label", text="Combinator"},
    {type = "menubutton", items={"abs", "avg"}, widthOverride=32, text="abs", callback=customWaveSet, id="waveEditMode"} },
  { labeledNumberField("Phase", "wavePhase", customWaveSet, true, 0, 1) },
  { labeledNumberField("Amplitude", "waveAmp", customWaveSet, true, -1, 1) },
}

local waveControls = {"waveMainMode", "waveLayerIndex", "waveIndex", "wavePhase",
  "waveAmp", "waveEditMenu", "waveEditMode",
  "waveLayerIndexUp", "waveLayerIndexDown",
  "waveIndexUp", "waveIndexDown",
  "wavePhaseUp", "wavePhaseDown", "waveAmpUp", "waveAmpDown"}
local function setupWaveControls(custom)
  if not custom then return end
  currentCustom = custom
  local inputs = layout.state.inputs
  inputs.waveLayerIndex:value(1)
  inputs.waveIndex:value(1)
  inputs.wavePhase:value(custom[1][1].shift or 0)
  inputs.waveAmp:value(custom[1][1].amp or 1)
  inputs.waveEditMenu:value(custom[1][1].wave)
  inputs.waveEditMenu:label(custom[1][1].wave)
  inputs.waveEditMode:value(custom[1].method)
  inputs.waveEditMode:label(custom[1].method)

  for i=1, #waveControls do
    inputs[waveControls[i]]:activate()
  end
end

local function waveSelectView(mb)
  local value
  if type(mb) == "string" then
    value = mb
  else
    value = mb:value()
  end
  layout.state.inputs.waveMenu:value(value)
  layout.state.inputs.waveMenu:label(value)
  if customWaves[value] then
    currentCustom = customWaves[value]
    setupWaveControls(customWaves[value])
  else
    for i=1, #waveControls do
      layout.state.inputs[waveControls[i]]:deactivate()
    end
  end
  current_wave = waves.generators[value] or buildWave(customWaves[value])
  layout.state.canvas.wavePreview:damage("user1")
end

local function addWave()
  custom = custom + 1
  local name = "custom"..custom
  customWaves[name] = { method = "abs", { method = "abs", { wave = "sine" } } }
  layout.state.inputs.synthWaveMenu:add(name)
  layout.state.inputs.waveMenu:add(name)
  waveSelectView(name)
end

local function removeWave()
  local name = layout.state.inputs.waveMenu:value()
  local sname = layout.state.inputs.synthWaveMenu:value()
  if customWaves[name] then
    layout.state.inputs.waveMenu:remove(name)
    layout.state.inputs.synthWaveMenu:remove(name)
    waveSelectView("sine")
    if sname == name then
      waveSelectSynth("sine")
    end
  end
end

local waveControls = { type = "_grid",
  { {type="menubutton", items={}, widthOverride = 64, text = "sine", callback=waveSelectView, id="waveMenu"},
    upDownButtons("waveAdd", addWave, removeWave)},
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
    layout.state.inputs.waveMenu:add(_waves[i])
    layout.state.inputs.waveEditMenu:add(_waves[i])
    layout.state.inputs.synthWaveMenu:add(_waves[i])
  end
  layout.state.inputs.waveEditMenu:add("none")
end

waveSelectView("sine")

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
