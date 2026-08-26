local commands, requests, system_messages = {}, {}, {}
local update_response = ""
local sequence_value = ""
local defer_session, deferred_session = false, nil
local defer_activation, deferred_activation = false, nil
local delayed, channel_ready = nil, false
local original_open = io.open
io.open = function(path, mode)
  local emitted = false
  return {
    write = function(_, value) if path == "streak-sequence.txt" then sequence_value = tostring(value) end end,
    read = function()
      if path == "control.key" then return string.rep("a", 44) end
      if path == "streak-sequence.txt" then return sequence_value end
      return ""
    end,
    lines = function() return function()
      if path == "panels.txt" and mode == "r" and not emitted then emitted = true; return "gilraennr" end
      return nil
    end end,
    close = function() end
  }
end

local snapshot_messages = {
  { id = "native-history", display_name = "History", message_text = "mensaje anterior", elements = function() return {} end }
}
local moderator_elements = setmetatable({ [1] = { type = "badge", tooltip = "Lead Moderator" } }, {
  __index = function(_, key)
    if key == "ipairs" then error("snapshot elements are not a regular Lua table") end
  end
})
local channel = {
  get_name = function() return "gilraennr" end,
  add_system_message = function(_, message) system_messages[#system_messages + 1] = message end,
  message_snapshot = function() return snapshot_messages end
}

_G.c2 = {
  HTTPMethod = { Get = "GET", Post = "POST" },
  HTTPRequest = { create = function(_, url)
    local request = { url = url }
    function request:set_header() end
    function request:set_timeout() end
    function request:set_payload(payload) self.payload = payload end
    function request:on_success(callback) self.success = callback end
    function request:on_error(callback) self.failure = callback end
    function request:finally() end
    function request:execute()
      requests[#requests + 1] = self
      if self.url:find("/control/activate", 1, true) then
		if defer_activation then deferred_activation = self
		else self.success({ status = function() return 200 end, data = function() return "" end }) end
      elseif self.url:find("/control/updates", 1, true) then
        self.success({ status = function() return 200 end, data = function() return update_response end })
	  elseif self.payload and self.payload:find('"kind":"stream_session"', 1, true) and defer_session then
		deferred_session = self
	  elseif self.success then
		self.success({ status = function() return 202 end, data = function() return "" end })
      end
    end
    return request
  end },
  Channel = { by_name = function() if channel_ready then return channel end end },
  later = function(callback) delayed = callback end,
  register_command = function(name, callback) commands[name] = callback end
}

dofile("chatterino-plugin/init.lua")
assert(#requests == 1 and requests[1].url:find("/control/activate", 1, true), "saved panel did not activate agent")
assert(type(delayed) == "function", "saved panel did not schedule a startup retry")
channel_ready = true
delayed()
assert(#requests == 3 and requests[2].payload:find("mensaje anterior", 1, true), "Twitch history was not replayed")
assert(requests[3].url:find("/control/updates", 1, true), "updates were not checked")
assert(type(delayed) == "function", "Chatterino 2.5.5 polling was not scheduled")
commands["/overlay"]({ words = { "/overlay" }, channel = channel })
assert(requests[5].payload:find('"kind":"stream_session"', 1, true), "Twitch session was not published")
snapshot_messages = {
  { id = "native-1", display_name = "Ana", message_text = "hola", username_color = "#112233",
    elements = function() return moderator_elements end },
  snapshot_messages[1]
}
delayed()
assert(#requests == 6, "native Twitch message was not published")
assert(requests[6].payload:find('"platform":"twitch"', 1, true), "wrong platform")
assert(requests[6].payload:find('"badges":["moderator"]', 1, true), "moderator badge missing")
snapshot_messages = {
  { id = "yt-chat-1", display_name = "Cris", message_text = "duplicate" },
  { id = "kick-chat-1", display_name = "Bob", message_text = "duplicate" },
  snapshot_messages[1], snapshot_messages[2]
}
delayed()
assert(#requests == 6, "plugin messages must not be duplicated")
defer_session = true
commands["/overlay"]({ words = { "/overlay" }, channel = channel })
commands["/overlay"]({ words = { "/overlay" }, channel = channel })
local pending_sessions = 0
for _, request in ipairs(requests) do
  if request.payload and request.payload:find('"kind":"stream_session"', 1, true) then
    pending_sessions = pending_sessions + 1
  end
end
assert(pending_sessions == 2, "overlapping activation must reuse the pending session")
snapshot_messages = {
  { id = "native-2", login_name = "luz", display_name = "Luz", message_text = "durante alta de sesión",
    elements = function() return {} end }
}
delayed()
assert(#requests == 8, "message must wait for session acceptance")
defer_session = false
deferred_session.success({ status = function() return 202 end, data = function() return "" end })
assert(#requests == 9 and requests[9].payload:find('"stream_id":"gilraennr:2"', 1, true),
  "accepted session must flush buffered messages with a fresh ID")
defer_activation = true
commands["/overlay"]({ words = { "/overlay" }, channel = channel })
commands["/overlay"]({ words = { "/overlay" }, channel = channel })
assert(#requests == 10, "overlapping control activation must be coalesced")
defer_activation = false
deferred_activation.success({ status = function() return 200 end, data = function() return "" end })
assert(#requests == 11 and requests[11].payload:find('"stream_id":"gilraennr:3"', 1, true),
  "completed control activation must start exactly one new session")
local fresh_channel = {
  get_name = function() return "fresh" end,
  add_system_message = function(_, message) system_messages[#system_messages + 1] = message end,
  message_snapshot = function()
    return { { id = "before-activation", display_name = "Old", message_text = "histórico" } }
  end
}
commands["/overlay"]({ words = { "/overlay", "fresh" }, channel = fresh_channel })
assert(requests[13].payload:find("histórico", 1, true) and not requests[13].payload:find('"stream_id"', 1, true),
  "pre-activation snapshot must not count toward the new session")
assert(requests[14].payload:find('"kind":"stream_session"', 1, true),
  "fresh panel must start its session after replaying history")
update_response = "Actualización disponible: test"
commands["/overlay"]({ words = { "/overlay", "updates" }, channel = channel })
assert(system_messages[#system_messages] == update_response, "manual update result was not shown")
io.open = original_open
print("bridge assertions: 19, failures: 0")
