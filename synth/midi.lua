-- midi communication
-- keeps as little state as possible; only governs raw midi input

local alsa = require("midialsa")

local mod = {}

local PEDAL_SUSTAIN = 64
local PEDAL_LOOP2 = 66
local PEDAL_LOOP = 67

local init = false

function mod.init(device)
  alsa.start()
  alsa.client("LuaSynthesizer", 1, 1, true)
  assert(alsa.connectfrom(0, alsa.parse_address(assert(device, "need midi device"))), "invalid midi device")
  init = true
end

function mod.check()
  return init and alsa.inputpending() > 0
end

local sustain, inLoop = false, false

local handlers = {}

function mod.handle(evt, func)
  if not alsa[evt] then error "cannot handle unknown event type" end
  handlers[alsa[evt]] = func
end

function mod.tick()
  if not init then return end

  if alsa.inputpending() > 0 then
    local evt = alsa.input()

    if handlers[evt[1]] then
      handlers[evt[1]](evt)
    end
  end
end

return mod
