local ENDPOINT = "http://127.0.0.1:8765/api/events"
local CONTROL_ENDPOINT = "http://127.0.0.1:8764/control/activate"
local PANELS_FILE = "panels.txt"
local STREAK_SEQUENCE_FILE = "streak-sequence.txt"
local handles, panels, seen, streak_panels, streak_pending, activation_pending = {}, {}, {}, {}, {}, {}
local heartbeat_started = false
local updates_checked = false

local function diagnostic(value)
  local file = io.open("status.txt", "w")
  if file then file:write(tostring(value), "\n"); file:close() end
end

local function read_control_token()
  local file = io.open("control.key", "r")
  if not file then return nil end
  local token = file:read("*a")
  file:close()
  return tostring(token or ""):gsub("%s+$", "")
end

local function check_updates(channel, mode, force)
  local token = read_control_token()
  if not token then return end
  local path, method = "/control/updates", c2.HTTPMethod.Get
  if mode == "on" or mode == "off" then
    path, method = "/control/updates/" .. mode, c2.HTTPMethod.Post
  else
    path = path .. "?manual=" .. (mode == "manual" and "1" or "0") .. "&force=" .. (force and "1" or "0")
  end
  pcall(function()
    local request = c2.HTTPRequest.create(method, "http://127.0.0.1:8764" .. path)
    request:set_header("Authorization", "Bearer " .. token)
    request:set_timeout(7000)
    if method == c2.HTTPMethod.Post then request:set_payload("{}") end
    request:on_success(function(response)
      local message = tostring(response:data() or "")
      if message ~= "" then channel:add_system_message(message) end
    end)
    request:on_error(function()
      if mode == "manual" then channel:add_system_message("No se pudieron comprobar las actualizaciones.") end
    end)
    request:finally(function() end)
    request:execute()
  end)
end

local function check_updates_once(channel)
  if updates_checked then return end
  updates_checked = true
  check_updates(channel, "auto", false)
end

local function activate_overlay(callback)
  local token = read_control_token()
  if not token or #token < 32 then callback(false); return end
  local ok = pcall(function()
    local request = c2.HTTPRequest.create(c2.HTTPMethod.Post, CONTROL_ENDPOINT)
    request:set_header("Authorization", "Bearer " .. token)
    request:set_header("Content-Type", "application/json")
    request:set_timeout(3000)
    request:set_payload("{}")
    request:on_success(function(response) callback(response:status() == 200) end)
    request:on_error(function() callback(false) end)
    request:finally(function() end)
    request:execute()
  end)
  if not ok then callback(false) end
end

local function start_heartbeat()
  if heartbeat_started or not c2.later then return end
  heartbeat_started = true
  local function heartbeat()
    local token = read_control_token()
    if token then
      pcall(function()
        local request = c2.HTTPRequest.create(c2.HTTPMethod.Post, "http://127.0.0.1:8764/control/heartbeat")
        request:set_header("Authorization", "Bearer " .. token)
        request:set_timeout(1000)
        request:set_payload("{}")
        request:on_success(function() end)
        request:on_error(function() end)
        request:finally(function() end)
        request:execute()
      end)
    end
    c2.later(heartbeat, 5000)
  end
  c2.later(heartbeat, 5000)
end

local function json_string(value)
  value = tostring(value or "")
  value = value:gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\b", "\\b")
  value = value:gsub("\f", "\\f"):gsub("\n", "\\n"):gsub("\r", "\\r"):gsub("\t", "\\t")
  return '"' .. value .. '"'
end

local function publish(panel, message)
  local id = tostring(message.id or "")
  if id:match("^kick%-chat%-") or id:match("^yt%-chat%-") then return end
  if streak_pending[panel] then
    local pending = streak_pending[panel]
    if #pending >= 100 then table.remove(pending, 1) end
    pending[#pending + 1] = message
    return
  end
  local author = tostring(message.display_name or message.login_name or "")
  local text = tostring(message.message_text or "")
  if author == "" or text == "" then return end
  local badges = {}
  pcall(function()
    local elements = message:elements()
    for index = 1, #elements do
      local element = elements[index]
      local element_type = tostring(element.type)
      local tooltip = tostring(element.tooltip or ""):lower()
      if element_type == "mod-badge" or tooltip:find("moderator", 1, true) or
          tooltip:find("moderador", 1, true) then
        badges[#badges + 1] = "moderator"
      end
    end
  end)
  diagnostic("message seen on " .. panel)
  local encoded_badges = {}
  for _, badge in ipairs(badges) do encoded_badges[#encoded_badges + 1] = json_string(badge) end
  local streak_fields = ""
  if streak_panels[panel] then
    streak_fields = '"channel":' .. json_string(panel) .. "," ..
      '"user_id":' .. json_string(message.login_name or author) .. "," ..
      '"stream_id":' .. json_string(streak_panels[panel]) .. ","
  end
  local payload = "{" ..
    '"panel":' .. json_string(panel) .. "," ..
    '"platform":"twitch","kind":"text_message",' ..
    '"id":' .. json_string(id) .. "," ..
    '"author":' .. json_string(author) .. "," ..
    streak_fields ..
    '"text":' .. json_string(text) .. "," ..
    '"color":' .. json_string(message.username_color or "") .. "," ..
    '"badges":[' .. table.concat(encoded_badges, ",") .. "]}"
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

local function next_session_id(panel)
  local sequence = 0
  local input = io.open(STREAK_SEQUENCE_FILE, "r")
  if input then sequence = tonumber(input:read("*a")) or 0; input:close() end
  sequence = sequence + 1
  local output = io.open(STREAK_SEQUENCE_FILE, "w")
  if output then output:write(tostring(sequence), "\n"); output:close() end
  return panel .. ":" .. tostring(sequence)
end

local function flush_streak_pending(panel, pending)
  if streak_pending[panel] ~= pending then return end
  streak_pending[panel] = nil
  for _, message in ipairs(pending) do publish(panel, message) end
end

local function publish_session(panel, pending, on_complete)
  local stream_id = next_session_id(panel)
  pending = pending or {}
  streak_pending[panel] = pending
  local payload = "{" ..
    '"panel":' .. json_string(panel) .. "," ..
    '"platform":"twitch","kind":"stream_session","text":"",' ..
    '"channel":' .. json_string(panel) .. "," ..
    '"stream_id":' .. json_string(stream_id) .. "}"
  local ok = pcall(function()
    local request = c2.HTTPRequest.create(c2.HTTPMethod.Post, ENDPOINT)
    request:set_header("Content-Type", "application/json")
    request:set_timeout(750)
    request:set_payload(payload)
    request:on_success(function(response)
      if response:status() == 202 then streak_panels[panel] = stream_id else streak_panels[panel] = nil end
      flush_streak_pending(panel, pending)
      if on_complete then on_complete() end
    end)
    request:on_error(function()
      streak_panels[panel] = nil
      flush_streak_pending(panel, pending)
      if on_complete then on_complete() end
    end)
    request:finally(function() end)
    request:execute()
  end)
  if not ok then
    streak_panels[panel] = nil
    flush_streak_pending(panel, pending)
    if on_complete then on_complete() end
  end
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

local function process_snapshot(channel, panel)
  local ok, messages = pcall(function() return channel:message_snapshot(100) end)
  -- Chatterino returns a userdata wrapper around the C++ snapshot, not a Lua table.
  if not ok or messages == nil then return false end
  seen[panel] = seen[panel] or {}
  for index = #messages, 1, -1 do
    local message = messages[index]
    local id = tostring(message.id or "")
    if id ~= "" and not seen[panel][id] then
      seen[panel][id] = true
      publish(panel, message)
    end
  end
  return true
end

local function attach(channel, panel)
  if handles[panel] then return true end
  local ok, handle = pcall(function()
    return channel:on_message_appended(function(message) publish(panel, message) end)
  end)
  if ok and handle then
    handles[panel], panels[panel] = handle, true
    process_snapshot(channel, panel)
    diagnostic("attached callback to " .. panel)
    return true
  end

  if not c2.later or not process_snapshot(channel, panel) then
    diagnostic("attach failed for " .. panel)
    return false
  end
  handles[panel], panels[panel] = true, true
  local function poll()
    if not handles[panel] then return end
    process_snapshot(channel, panel)
    c2.later(poll, 500)
  end
  c2.later(poll, 500)
  diagnostic("attached polling to " .. panel)
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
    if panel then panels[panel] = true end
  end
  file:close()
end

local function attach_saved_panels(attempt)
  local pending = false
  for panel in pairs(panels) do
    if not handles[panel] then
      local ok, channel = pcall(c2.Channel.by_name, panel)
      if ok and channel then
        if attach(channel, panel) then check_updates_once(channel) end
      else
        diagnostic("waiting for panel, attempt " .. tostring(attempt))
      end
      if not handles[panel] then pending = true end
    end
  end
  if pending and attempt < 60 and c2.later then
    c2.later(function() attach_saved_panels(attempt + 1) end, 500)
  end
end

c2.register_command("/overlay", function(ctx)
  local requested = tostring(ctx.words[2] or "")
  if requested == "updates" then
    local action = tostring(ctx.words[3] or "")
    if action == "on" or action == "off" then check_updates(ctx.channel, action, false)
    elseif action == "" or action == "check" then check_updates(ctx.channel, "manual", action == "check")
    else ctx.channel:add_system_message("Uso: /overlay updates [check|on|off]") end
    return
  end
  local panel = normalized_panel(requested ~= "" and requested or ctx.channel:get_name())
  if not panel then
    ctx.channel:add_system_message("Overlay: panel inválido. Uso: /overlay [panel]")
    return
  end
  if activation_pending[panel] then
    ctx.channel:add_system_message("Overlay: activación en curso.")
    return
  end
  activation_pending[panel] = true
  local pending = nil
  if handles[panel] then
    pending = {}
    streak_pending[panel] = pending
  end
  streak_panels[panel] = nil
  local function finish_activation()
    activation_pending[panel] = nil
  end
  activate_overlay(function(active)
    if not active then
      if pending then flush_streak_pending(panel, pending) end
      finish_activation()
      ctx.channel:add_system_message("Overlay: no se pudo activar el agente local; reinstala el plugin")
      return
    end
    start_heartbeat()
    if not attach(ctx.channel, panel) then
      if pending then flush_streak_pending(panel, pending) end
      finish_activation()
      ctx.channel:add_system_message("Overlay: Chatterino no permite capturar este panel")
      return
    end
    publish_session(panel, pending, finish_activation)
    save_panels()
    ctx.channel:add_system_message("Overlay OBS activo: http://127.0.0.1:8765/overlay/" .. panel)
    check_updates_once(ctx.channel)
  end)
end)

restore_panels()
diagnostic("plugin loaded")
if next(panels) then
  activate_overlay(function(active)
    if active then start_heartbeat(); attach_saved_panels(1) else diagnostic("overlay agent unavailable") end
  end)
end
