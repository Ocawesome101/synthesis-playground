local mod = {}

local function serialize(k, v)
  local t = ""
  if type(k) ~= "number" then
    t = t .. k .. "="
  end
  if type(v) == "table" then
    t = t .. mod.serialize(v) .. ","
  elseif type(v) == "number" then
    t = t .. string.format("%f,", v)
  else
    t = t .. string.format("%q,",v)
  end
  return t
end

function mod.serialize(tab)
  local text = "{"
  for k, v in pairs(tab) do
    if type(k) ~= "number" then
      text = text .. serialize(k, v)
    end
  end
  for i=1, #tab do
    text = text .. serialize(i, tab[i])
  end
  return text .. "}"
end

function mod.unserialize(text)
  return assert(load("return " .. text, "=unserialize", "t", {}))()
end

return mod
