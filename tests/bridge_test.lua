local commands, requests = {}, {}
local delayed, channel_ready = nil, false
local original_open = io.open
io.open = function(_, mode)
  local emitted = false
  return {
    write = function() end,
    lines = function() return function()
      if mode == "r" and not emitted then emitted = true; return "gilraennr" end
      return nil
    end end,
    close = function() end
  }
end

local snapshot_messages = {
  { id = "native-history", display_name = "History", message_text = "mensaje anterior", elements = function() return {} end }
}
local channel = {
  get_name = function() return "gilraennr" end,
  add_system_message = function() end,
  message_snapshot = function() return snapshot_messages end
}

_G.c2 = {
  HTTPMethod = { Post = "POST" },
  HTTPRequest = { create = function(_, url)
    local request = { url = url }
    function request:set_header() end
    function request:set_timeout() end
    function request:set_payload(payload) self.payload = payload end
    function request:on_success() end
    function request:on_error() end
    function request:finally() end
    function request:execute() requests[#requests + 1] = self end
    return request
  end },
  Channel = { by_name = function() if channel_ready then return channel end end },
  later = function(callback) delayed = callback end,
  register_command = function(name, callback) commands[name] = callback end
}

dofile("chatterino-plugin/init.lua")
assert(type(delayed) == "function", "saved panel did not schedule a startup retry")
channel_ready = true
delayed()
assert(#requests == 1 and requests[1].payload:find("mensaje anterior", 1, true), "Twitch history was not replayed")
assert(type(delayed) == "function", "Chatterino 2.5.5 polling was not scheduled")
commands["/overlay"]({ words = { "/overlay" }, channel = channel })
snapshot_messages = {
  { id = "native-1", display_name = "Ana", message_text = "hola", username_color = "#112233",
    elements = function() return { { type = "mod-badge" } } end },
  snapshot_messages[1]
}
delayed()
assert(#requests == 2, "native Twitch message was not published")
assert(requests[2].payload:find('"platform":"twitch"', 1, true), "wrong platform")
assert(requests[2].payload:find('"badges":["moderator"]', 1, true), "moderator badge missing")
snapshot_messages = {
  { id = "yt-chat-1", display_name = "Cris", message_text = "duplicate" },
  { id = "kick-chat-1", display_name = "Bob", message_text = "duplicate" },
  snapshot_messages[1], snapshot_messages[2]
}
delayed()
assert(#requests == 2, "plugin messages must not be duplicated")
io.open = original_open
print("bridge assertions: 8, failures: 0")
