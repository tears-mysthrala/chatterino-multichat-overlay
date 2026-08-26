local ENDPOINT = "http://127.0.0.1:8765/api/events"
local PANELS_FILE = "data/panels.txt"
local handles, panels = {}, {}

local function json_string(value)
  value = tostring(value or "")
  value = value:gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\b", "\\b")
  value = value:gsub("\f", "\\f"):gsub("\n", "\\n"):gsub("\r", "\\r"):gsub("\t", "\\t")
  return '"' .. value .. '"'
end

local function publish(panel, message)
  local id = tostring(message.id or "")
  if id:match("^kick%-chat%-") or id:match("^yt%-chat%-") then return end
  local author = tostring(message.display_name or message.login_name or "")
  local text = tostring(message.message_text or "")
  if author == "" or text == "" then return end
  local payload = "{" ..
    '"panel":' .. json_string(panel) .. "," ..
    '"platform":"twitch","kind":"text_message",' ..
    '"id":' .. json_string(id) .. "," ..
    '"author":' .. json_string(author) .. "," ..
    '"text":' .. json_string(text) .. "," ..
    '"color":' .. json_string(message.username_color or "") .. "}"
  pcall(function()
    local request = c2.HTTPRequest.create(c2.HTTPMethod.Post, ENDPOINT)
    request:set_header("Content-Type", "application/json")
    request:set_timeout(750)
    request:set_payload(payload)
    request:on_success(function() end)
    request:on_error(function() end)
    request:finally(function() end)
    request:execute()
  end)
end

local function save_panels()
  local file = io.open(PANELS_FILE, "w")
  if not file then return end
  local names = {}
  for name in pairs(panels) do names[#names + 1] = name end
  table.sort(names)
  for _, name in ipairs(names) do file:write(name, "\n") end
  file:close()
end

local function attach(channel, panel)
  if handles[panel] then return true end
  local ok, handle = pcall(function()
    return channel:on_message_appended(function(message) publish(panel, message) end)
  end)
  if not ok or not handle then return false end
  handles[panel], panels[panel] = handle, true
  return true
end

local function normalized_panel(value)
  local panel = tostring(value or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
  if not panel:match("^[a-z0-9_%-]+$") then return nil end
  return panel
end

local function restore_panels()
  local file = io.open(PANELS_FILE, "r")
  if not file then return end
  for line in file:lines() do
    local panel = normalized_panel(line)
    if panel then
      local ok, channel = pcall(c2.Channel.by_name, panel)
      if ok and channel then attach(channel, panel) end
    end
  end
  file:close()
end

c2.register_command("/overlay", function(ctx)
  local requested = tostring(ctx.words[2] or "")
  local panel = normalized_panel(requested ~= "" and requested or ctx.channel:get_name())
  if not panel then
    ctx.channel:add_system_message("Overlay: panel inválido. Uso: /overlay [panel]")
    return
  end
  if not attach(ctx.channel, panel) then
    ctx.channel:add_system_message("Overlay: Chatterino no permite capturar este panel")
    return
  end
  save_panels()
  ctx.channel:add_system_message("Overlay OBS activo: http://127.0.0.1:8765/overlay/" .. panel)
end)

restore_panels()
