-- main file

local lanes = require("lanes").configure()
local fl = require("moonfltk")
local layout = require("synth.layout")
local waves = require("synth.waves")

local linda1 = lanes.linda()
local linda2 = lanes.linda()
local device = (...)

local KEY_FROMSYNTH = "SynthSend"
local KEY_TOSYNTH = "SynthRecv"
local KEY_SAMPLEGEN = "SampleGen"
local _DEBUG = false
local DEBUG = _DEBUG and print or function() end

---== SYNTHESIZER ==---
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
  local sampleUse = {}
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
    if sampleUse[channel] then
      local s = samples[sampleUse[channel]]
      if s[pitch - 20] then
        return snd.startNote(pitch, velocity, s[pitch - 20], channel)
      end
    end
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
        DEBUG("change channel: " .. v[2])
        channel = v[2]
        if not held[channel] then held[channel] = {} end
        linda1:send(KEY_FROMSYNTH, {"sample", channel, sampleUse[channel]})
      elseif k and v[1] == "wave" then
        DEBUG("change wave: " .. v[2])
        wave[channel] = waves.generators[v[2]] or custom[v[2]] or function() end
      elseif k and v[1] == "custom" then
        DEBUG("update custom wave: " .. v[2])
        custom[v[2]] = v[3]
      elseif k and samples[sample] and v[1] == "addsample" then
        DEBUG("add sample PCM: " .. v[2] .. ", " .. #v[3] .. " bytes")
        samples[sample][v[2]] = v[3]
      elseif k and v[1] == "playsample" then
        DEBUG("preview sample")
        snd.startNote(0, 128, v[2], channel)
      elseif k and v[1] == "sampleset" then
        DEBUG("add sample set: " .. v[2])
        sample = v[2]
        samples[sample] = samples[sample] or {}
      elseif k and v[1] == "sample" then
        DEBUG("use sample set for channel " .. channel .. ": " .. v[2])
        sampleUse[channel] = v[2]
        if not samples[v[2]] then
          linda1:send(KEY_FROMSYNTH, {"samplerequest", v[2]})
        end
        linda1:send(KEY_FROMSYNTH, {"sample", channel, v[2]})
      elseif k and v[1] == "nosample" then
        DEBUG("no sample set for channel " .. channel)
        sampleUse[channel] = nil
        linda1:send(KEY_FROMSYNTH, {"sample", channel, false})
      end
    until not k
    util.sleep(10)
  end
end)

local function generateSample(N, generators, duration, sample)
  local snd = require("synth.snd")
  local samples = duration * snd.SAMPLE_RATE
  local perCycle = {}
  local durations = {}
  for i=1, #generators do
    perCycle[i] = math.floor(snd.SAMPLE_RATE/snd.freq(20+N+sample[i].pitch)+0.5)
    durations[i] = sample[i].duration * samples
  end
  local data = {}
  for i=1, samples do
    local values = {}
    for g=1, #generators do
      if i <= durations[g] then
        local s = sample[g]
        local amp = s.ampStart + (s.ampEnd-s.ampStart)*((i/(durations[g]))^s.linearity)
        values[#values+1] = math.floor(generators[g](i, perCycle[g]) * amp * snd.SAMPLE_MAX + 0.5)
      else
        values[#values+1] = 0
      end
    end
    if sample.method == "avg" then
      data[i] = math.floor(waves.avg(values) + 0.5)
    elseif sample.method == "max" then
      data[i] = math.max(table.unpack(values))
    elseif sample.method == "abs" then
      data[i] = waves.abs(values)
    end
  end
  return waves.getPCMString(data)
end

-- takes a list of generators, a main duration, and sample info
local samplegen_thread = lanes.gen("*", function(generators, duration, sample)
  for N=1, 88 do
    local sampleData = generateSample(N, generators, duration, sample)
    linda2:send(KEY_SAMPLEGEN, {"generated", N})
    linda1:send(KEY_TOSYNTH, {"addsample", N, sampleData})
  end
end)

local synth = synth_thread()
if synth.status == "error" then
  local _ = synth[1]
  return
end

local snd = require("synth.snd")
local ser = require("synth.serialize")

---== UTILITY FUNCTIONS ==---
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
      elseif layer.method == "max" then
        fvalues[l] = math.max(table.unpack(lvalues))
      end
    end
    if custom.method == "abs" then
      return waves.abs(fvalues)
    elseif custom.method == "avg" then
      return waves.avg(fvalues)
    elseif custom.method == "max" then
      return math.max(table.unpack(fvalues))
    end
  end
end

local function synthSetChannel()
  linda1:send(KEY_TOSYNTH, {"channel", tonumber(layout.state.inputs.channel:value()) or 0})
end

local function e(t) return function(T) T.type = t return T end end
local grid = e "_grid"
local label = e "label"
local button = e "button"
local canvas = e "canvas"
local number = e "number"
local flasher = e "flasher"
local buttonHalf = e "buttonHalf"
local menubutton = e "menubutton"
local waveLists = {}
local function waveList(e)
  e.type = "menubutton"
  waveLists[#waveLists+1] = e.id
  return e
end
local sampleLists = {}
local function sampleList(e)
  e.type = "menubutton"
  sampleLists[#sampleLists+1] = e.id
  return e
end

local current_wave = waves.generators.sine
local currentCustom
local customWaves = {}
local waveCombinators = {"avg", "abs", "max"}

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

local function waveSelectSample(mb)
  local value
  if type(mb) == "string" then value = mb else value = mb:value() end
  layout.state.inputs.synthSampleMenu:value(value)
  layout.state.inputs.synthSampleMenu:label(value)
  if value == "--" then
    linda1:send(KEY_TOSYNTH, {"nosample"})
  else
    linda1:send(KEY_TOSYNTH, {"sample", value})
  end
end

local function upDownButtons(id, up, down)
  return grid {nobg=true,
    {buttonHalf {text="+",callback=up,id=id.."Up"}},
    {buttonHalf {text="-",callback=down,id=id.."Down"}}}
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
    label {widthOverride="remaining", text=name, widthOverride="remaining"},number {float=float,id=id,callback=callSet,value="0",text="0"},
    upDownButtons(id, callUp, callDown)
end

---== WAVEFORM CONTROLS ==---
local function wavePreview(self)
  if not self then return end
  self:super_draw()
  local x, y, w, h = self:xywh()
  fl.color(0x44FF4400)
  fl.begin_points()
  for step=1, 64 do
    fl.vertex(x+step+layout.MARGIN, y+32+layout.MARGIN+math.floor(current_wave(step, 64)*-32))
  end
  fl.end_points()
end

local function waveSetParams(mb)
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
  layout.state.canvas.wavePreview:redraw()

  for name, val in pairs(customWaves) do
    if val == currentCustom then waveSelectSynth(name) break end
  end
end

local custom = 0

local waveControlIDs = {"waveMainMode", "waveLayerIndex", "waveIndex", "wavePhase",
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

  for i=1, #waveControlIDs do
    inputs[waveControlIDs[i]]:activate()
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
    for i=1, #waveControlIDs do
      layout.state.inputs[waveControlIDs[i]]:deactivate()
    end
  end
  current_wave = waves.generators[value] or buildWave(customWaves[value])
  layout.state.canvas.wavePreview:redraw()
end

local function waveAdd(name, data)
  if type(name) ~= "string" then
    custom = custom + 1
    name = "custom"..custom
  end
  customWaves[name] = data or { method = "abs", { method = "abs", { wave = "sine" } } }
  for i=1, #waveLists do
    layout.state.inputs[waveLists[i]]:add(name)
  end
  waveSelectView(name)
end

local function waveRemove()
  local name = layout.state.inputs.waveMenu:value()
  local sname = layout.state.inputs.synthWaveMenu:value()
  if customWaves[name] then
    for i=1, #waveLists do
      layout.state.inputs[waveLists[i]]:remove(name)
    end
    layout.state.inputs.waveMenu:remove(name)
    waveSelectView("sine")
    if sname == name then
      waveSelectSynth("sine")
    end
  end
end

---== SAMPLER CONTROLS ==---
local samples, sample = {}
local samplerToggle = {
  "sampleAddDown", "waveSelectSampler", "samplerMethod", "samplerLayer", "samplerAmpStart",
  "samplerAmpEnd", "samplerLinearity", "samplerPhase", "samplerDuration", "samplerUploadChannel",
  "samplerUploadDuration", "samplerUploadPreview", "samplerUpload", "samplerUploadDurationUp", "samplerUploadDurationDown",
  "samplerUploadChannelUp", "samplerUploadChannelDown",
  "samplerLayerUp", "samplerLayerDown",
  "samplerAmpStartUp", "samplerAmpStartDown",
  "samplerAmpEndUp", "samplerAmpEndDown",
  "samplerLinearityUp", "samplerLinearityDown",
  "samplerPhaseUp", "samplerPhaseDown",
  "samplerDurationUp", "samplerDurationDown",
  "samplerPitchShift",
  "samplerPitchShiftUp", "samplerPitchShiftDown",
  "samplerPreviewPitch",
  "samplerPreviewPitchUp", "samplerPreviewPitchDown",
}

local sampleN = 0
local function samplerAdd(name, data)
  if type(name) ~= "string" then
    sampleN = sampleN + 1
    name = "sample" .. sampleN
  end
  samples[name] = data or {
    method = "avg", {wave = "sine", ampStart = 1, ampEnd = 0, linearity = 1, shift = 0, duration = 1, pitch = 0}} 
  sample = name
  local inputs = layout.state.inputs
  inputs.waveSelectSampler:value("sine")
  for i=1, #sampleLists do
    inputs[sampleLists[i]]:add(name)
  end
  inputs.samplerSelect:value(name)
  inputs.samplerSelect:label(name)
  inputs.samplerAmpStart:value(samples[name][1].ampStart)
  inputs.samplerAmpEnd:value(samples[name][1].ampEnd)
  inputs.samplerLinearity:value(samples[name][1].linearity)
  inputs.samplerLayer:value(1)
  inputs.samplerPhase:value(samples[name][1].shift)
  inputs.samplerPitchShift:value(samples[name][1].pitch)
  inputs.samplerDuration:value(samples[name][1].duration)
  layout.state.canvas.samplerPreview:redraw()
  layout.state.canvas.samplerPreviewAmp:redraw()
  layout.state.canvas.samplerPreviewWave:redraw()
  for i=1, #samplerToggle do
    layout.state.inputs[samplerToggle[i]]:activate()
  end
end

local function samplerRemove() end

local colors = {
  0xff444400,
  0x44ff4400,
  0xffff4400,
}
local function samplerPreviewAmp(self)
  self:super_draw()
  if not sample or not samples[sample] then return end
  local s = samples[sample]
  local x, y, w, h = self:xywh()
  for i=1, #s do
    fl.color(colors[i%3+1])
    fl.begin_points()
    for step=1, 64 do
      local amp = s[i].ampStart + (s[i].ampEnd-s[i].ampStart)*((step/64)^s[i].linearity)
      fl.vertex(x+step+layout.MARGIN, y+32+layout.MARGIN-math.floor(amp*32))
    end
    fl.end_points()
  end
end

local function samplerPreviewWave(self)
  self:super_draw()
  if not sample or not samples[sample] then return end
  local generators = {}
  local s = samples[sample]
  for i=1, #s do
    if s[i].wave == "noise" then
      generators[i] = require("synth.noise").noiseGenerator()
    else
      generators[i] = waves.generators[s[i].wave] or buildWave(customWaves[s[i].wave])
    end
  end
  local x, y, w, h = self:xywh()
  for i=1, #generators do
    fl.color(colors[i%3+1])
    fl.begin_points()
    for step=1, 64 do
      local amp = s[i].ampStart + (s[i].ampEnd-s[i].ampStart)*((step/64)^s[i].linearity)
      fl.vertex(x+step+layout.MARGIN, y+32+layout.MARGIN+math.floor(generators[i](step, 16) * amp * -32))
    end
    fl.end_points()
  end
  fl.end_points()

  if #samples == 0 or not sample then return end
end

local function samplerGetGenerator(cycles)
  if not sample or not samples[sample] then return function() end end
  local s = samples[sample]
  local generators = {}
  for i=1, #s do
    if s[i].wave == "noise" then
      generators[i] = require("synth.noise").noiseGenerator()
    elseif s[i].wave ~= "none" then
      generators[i] = waves.generators[s[i].wave] or buildWave(customWaves[s[i].wave])
    end
  end
  cycles = cycles or 1
  return function(cur, max)
    local values = {}
    for i=1, #generators do
      local amp = s[i].ampStart + (s[i].ampEnd-s[i].ampStart)*((cur/max)^s[i].linearity)
      values[i] = generators[i](cur, (max/cycles)+s[i].pitch) * amp
    end
    local value
    if s.method == "avg" then
      value = waves.avg(values)
    elseif s.method == "abs" then
      value = waves.abs(values)
    elseif s.method == "max" then
      value = math.max(table.unpack(values))
    end
    return value
  end
end

local function samplerPreview(self)
  self:super_draw()
  if not sample or not samples[sample] then return end
  local x, y, w, h = self:xywh()
  fl.color(0xFF44FF00)
  fl.begin_points()
  local generator = samplerGetGenerator(16)
  for step=1, w do
    local value = generator(step, w)
    fl.vertex(x + layout.MARGIN + step, y + layout.MARGIN + 32 + value * -32)
  end
  fl.end_points()
end

local lastWave
local function samplerGetParams(_, shouldOverwrite, waveOverride)
  for i=1, #samplerToggle do
    layout.state.inputs[samplerToggle[i]]:deactivate()
  end
  if not sample or not samples[sample] then return end
  for i=1, #samplerToggle do
    layout.state.inputs[samplerToggle[i]]:activate()
  end

  local s = samples[sample]
  local inputs = layout.state.inputs
  local iwave = shouldOverwrite and 1 or tonumber(inputs.samplerLayer:value())
  if shouldOverwrite or not lastWave then lastWave = iwave end
  shouldOverwrite = shouldOverwrite or iwave ~= lastWave
  lastWave = iwave
  s[iwave] = s[iwave] or {wave = "sine", ampStart=1, ampEnd=0, linearity = 1, shift = 0, duration = 1, pitch = 0}
  local wave = shouldOverwrite and waveOverride or s[iwave].wave
  local method = s.method
  local ampStart, ampEnd, linearity = s[iwave].ampStart, s[iwave].ampEnd, s[iwave].linearity
  local phase = s[iwave].shift or 0
  local shift = s[iwave].pitch or 0
  local duration = s[iwave].duration or 1

  if not shouldOverwrite then
    wave = inputs.waveSelectSampler:value()
    method = inputs.samplerMethod:value()
    ampStart, ampEnd, linearity = tonumber(inputs.samplerAmpStart:value()), tonumber(inputs.samplerAmpEnd:value()),
      tonumber(inputs.samplerLinearity:value())
    phase = tonumber(inputs.samplerPhase:value())
    shift = tonumber(inputs.samplerPitchShift:value())
    duration = tonumber(inputs.samplerDuration:value())
  end

  s[iwave].ampStart = ampStart
  s[iwave].ampEnd = ampEnd
  s[iwave].linearity = linearity
  s[iwave].wave = wave
  s[iwave].shift = phase
  s[iwave].pitch = shift
  s[iwave].duration = duration
  s.method = method

  inputs.samplerMethod:value(method)
  inputs.samplerMethod:label(method)

  inputs.waveSelectSampler:value(wave)
  inputs.waveSelectSampler:label(wave)
  inputs.samplerAmpStart:value(ampStart)
  inputs.samplerAmpEnd:value(ampEnd)
  inputs.samplerLinearity:value(linearity)
  inputs.samplerPhase:value(phase)
  inputs.samplerPitchShift:value(shift)
  inputs.samplerDuration:value(duration)

  layout.state.canvas.samplerPreview:redraw()
  layout.state.canvas.samplerPreviewAmp:redraw()
  layout.state.canvas.samplerPreviewWave:redraw()
end

local function samplerSelect(mb)
  sample = mb:value()
  mb:label(sample)
  samplerGetParams(_, true)
end

local sample_gen
local function uploadSamples(_sample)
  _sample = _sample or sample
  local s = samples[_sample]
  local generators = {}
  for i=1, #s do
    if s[i].wave == "noise" then
      generators[i] = require("synth.noise").noiseGenerator()
    elseif s[i].wave ~= "none" then
      generators[i] = waves.generators[s[i].wave] or buildWave(customWaves[s[i].wave])
    end
  end

  local duration = tonumber(layout.state.inputs.samplerUploadDuration:value())

  linda1:send(KEY_TOSYNTH, {"sampleset", _sample})
  linda1:send(KEY_TOSYNTH, {"sample", _sample})
  sample_gen = samplegen_thread(generators, duration, s)
end

local function previewSample()
  local s = samples[sample]
  local generators = {}
  for i=1, #s do
    if s[i].wave == "noise" then
      generators[i] = require("synth.noise").noiseGenerator()
    elseif s[i].wave ~= "none" then
      generators[i] = waves.generators[s[i].wave] or buildWave(customWaves[s[i].wave])
    end
  end

  local duration = tonumber(layout.state.inputs.samplerUploadDuration:value())
  local pitch = tonumber(layout.state.inputs.samplerPreviewPitch:value())

  linda1:send(KEY_TOSYNTH, {"playsample", generateSample(pitch-20, generators, duration, s)})
end

---== LOAD/SAVE ==---
local function loadButton(ext, add, text)
  return button {
    text = text or "Load", callback = function()
      local chooser = fl.native_file_chooser()
      chooser:filter("*."..ext)
      chooser:directory(os.getenv("PWD") or os.getenv("HOME") or "/")
      local res = chooser:show()
      if res == "cancel" or not res then return end
      local filename = chooser:filename()
      local handle, err = io.open(filename, "r")
      if not handle then return fl.alert(err) end
      local name = filename:match("/(^/+)$")
      add(name, ser.unserialize(handle:read("a")))
      handle:close()
    end
  }
end

local function saveButton(tab, mbKey, ext, text)
  return button {
    text = text or "Save", callback = function()
      local name = layout.state.inputs[mbKey]:value()
      if not tab[name] then return fl.alert("Not saveable") end
      local chooser = fl.native_file_chooser("save file")
      chooser:filter("*."..ext)
      chooser:directory(os.getenv("PWD") or os.getenv("HOME") or "/")
      chooser:options("saveas confirm", "use filter ext")
      if not name then return end
      chooser:preset_file(name.."."..ext)
      local res = chooser:show()
      if res == "cancel" or not res then return end
      local filename = chooser:filename()
      local handle, err = io.open(filename, "w")
      if not handle then return fl.alert(err) end
      handle:write(ser.serialize(tab[name]))
      handle:close()
    end
  }
end

local function loadSaveControl(tab, mbKey, ext, funcAdd, textLoad, textSave, vert)
  local l, s = loadButton(ext, funcAdd, textLoad), saveButton(tab, mbKey, ext, textSave)
  if vert then
    return grid { nobg = true,
      { l },
      { s }
    }
  else
    return grid { nobg = true,
      { l, s }
    }
  end
end

---== GUI STRUCTRURE ==---
local synthControls = grid { widthOverride = "remaining",
  { -- row 1: indicators
    flasher {text="Sample", color=0x00FF00},
    flasher {text="Loop",color=0xFF0000} },
  { -- row 2: channel
    labeledNumberField("Channel:", "channel", synthSetChannel, nil, 0) },
  { -- row 3: wave
    label {widthOverride="remaining", text="Wave:"},
    waveList {text="sine", items={}, callback=waveSelectSynth, widthOverride = "remaining", id="synthWaveMenu"}
  },
  { -- row 3: sample set
    label {widthOverride="remaining", text="Sample:"},
    sampleList {text = "--", widthOverride = "remaining",items={"--"},callback=waveSelectSample, id="synthSampleMenu"},
  }
}

local waveControls = grid {
  { waveList {items={}, widthOverride = 64, text = "sine", callback=waveSelectView, id="waveMenu"},
    upDownButtons("waveAdd", waveAdd, waveRemove),
    loadSaveControl(customWaves, "waveMenu", "spw", waveAdd)},
  {
    { type = "canvas", w = 64, h = 64, draw = wavePreview, id = "wavePreview" },
    grid {
      {
        label {widthOverride="remaining", text="Main Combinator"},
        menubutton {items=waveCombinators, widthOverride=32, text="abs", callback=waveSetParams, id="waveMainMode"} },
      {
        labeledNumberField("Layer", "waveLayerIndex", waveSetParams, nil, 1) },
      {
        label {widthOverride="remaining", text="Layer Combinator"},
        menubutton {items=waveCombinators, widthOverride=32, text="abs", callback=waveSetParams, id="waveEditMode"} },
      {
        labeledNumberField("Wave", "waveIndex", waveSetParams, nil, 1) },
      {
        label {widthOverride="remaining", text = "Generator"},
        menubutton {items={}, widthOverride = 64, text = "sine", callback=waveSetParams, id="waveEditMenu"} },
      {
        labeledNumberField("Phase", "wavePhase", waveSetParams, true, 0, 1) },
      {
        labeledNumberField("Amplitude", "waveAmp", waveSetParams, true, -1, 1) },
    }, }
}

local samplerControls = grid { widthOverride = "remaining",
  { -- row 1: selection
    sampleList {text = "--", widthOverride = "remaining", items={}, callback=samplerSelect, id="samplerSelect"},
    upDownButtons("sampleAdd", samplerAdd, samplerRemove) },
  { -- row 2: previews (amplitude, wave)
    canvas {w = 64, h = 64, id = "samplerPreviewAmp", draw = samplerPreviewAmp},
    canvas {w = 64, h = 64, id = "samplerPreviewWave", draw = samplerPreviewWave},
    loadSaveControl(samples, "samplerSelect", "sps", samplerAdd, "L", "S", true) },
  { -- row 3+: controls
    label {widthOverride="remaining", text="Combinator"},
    menubutton {items = waveCombinators, widthOverride = 32, text = "avg", callback = samplerGetParams, id = "samplerMethod"} },
  {
    labeledNumberField("Layer", "samplerLayer", samplerGetParams, false, 1) },
  {
    label {widthOverride="remaining", text="Wave"}, waveList {text = "sine", widthOverride = 64,
      items={}, callback=samplerGetParams, id="waveSelectSampler" }, },
  {
    labeledNumberField("Amp start", "samplerAmpStart", samplerGetParams, true, -1, 1), },
  {
    labeledNumberField("Amp end", "samplerAmpEnd", samplerGetParams, true, -1, 1), },
  {
    labeledNumberField("Linearity", "samplerLinearity", samplerGetParams, true, 0.1, 4) },
  {
    labeledNumberField("Phase", "samplerPhase", samplerGetParams, true, 0, 1) },
  {
    labeledNumberField("Pitch Shift", "samplerPitchShift", samplerGetParams, false) },
  {
    labeledNumberField("Duration", "samplerDuration", samplerGetParams, true, 0.1, 1) },
}

local samplerUploadControls = grid { widthOverride = "remaining",
  { canvas {widthOverride = "remaining", w = 64, h = 64, id = "samplerPreview", draw = samplerPreview} },
  { button {text = "Preview", callback = previewSample, id = "samplerUploadPreview"},
    button {text = "Generate Samples", callback = uploadSamples, id = "samplerUpload"},
    label {text = "0/88", id = "samplerGenerated"} },
  { labeledNumberField("Synthesizer upload channel", "samplerUploadChannel", function() end, false, 0) },
  { labeledNumberField("Sample duration", "samplerUploadDuration", function() end, true, 0.1) },
  { labeledNumberField("Preview pitch", "samplerPreviewPitch", function() end, false, 21, 100) },
}

local ui
local uiGrid = grid {
  { grid { nobg=true,
    { synthControls },
    { samplerControls },
  }, grid {nobg=true,
    { waveControls },
    { samplerUploadControls },
  }, },
}

fl.option("uses gtk", false)
layout.init()
ui = layout.layout(uiGrid)
layout.present()

do
  layout.state.inputs.samplerUploadDuration:value(3)
  layout.state.inputs.samplerPreviewPitch:value(57)
  layout.state.inputs.waveSelectSampler:add("none")
  layout.state.inputs.waveSelectSampler:add("noise")
  local _waves = {}
  for wave, _ in pairs(waves.generators) do
    _waves[#_waves+1] = wave
  end
  table.sort(_waves)
  for i=1, #_waves do
    for j=1, #waveLists do
      layout.state.inputs[waveLists[j]]:add(_waves[i])
    end
    layout.state.inputs.waveEditMenu:add(_waves[i])
  end
  layout.state.inputs.waveEditMenu:add("none")

  for i=1, #samplerToggle do
    layout.state.inputs[samplerToggle[i]]:deactivate()
  end
end

waveSelectView("sine")

fl.set_timeout(0.05, true, function() end)

while fl.wait() do
  if synth.status == "error" then
    local _ = synth[1]
    fl.quit()
    break
  end
  if sample_gen and sample_gen.status == "error" then
    local _ = sample_gen[1]
    sample_gen = nil
  end
  repeat
    local k, v = linda1:receive(0, KEY_FROMSYNTH)
    if not k then k, v = linda2:receive(0, KEY_SAMPLEGEN) end
    if k and v[1] == "inLoop" then
      if v[2] then
        layout.state.flashers.Loop:setBright()
      else
        layout.state.flashers.Loop:setDim()
      end
    elseif k and v[1] == "generated" then
      layout.state.labels.samplerGenerated:label(v[2].."/88")
      layout.state.window:redraw()
    elseif k and v[1] == "sample" then
      if v[3] then
        layout.state.flashers.Sample:setBright()
        if type(v[3]) == "string" then
          layout.state.inputs.synthSampleMenu:value(v[3])
          layout.state.inputs.synthSampleMenu:label(v[3])
        end
      else
        layout.state.flashers.Sample:setDim()
      end
    elseif k and v[1] == "samplerequest" then
      if v[2] and samples[v[2]] then
        uploadSamples(v[2])
      end
    end
  until not k
end
