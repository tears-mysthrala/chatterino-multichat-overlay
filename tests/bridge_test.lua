local commands, requests = {}, {}
local original_open = io.open
io.open = function()
  return {
    write = function() end,
    lines = function() return function() return nil end end,
    close = function() end
  }
end

local appended
local channel = {
  get_name = function() return "gilraennr" end,
  add_system_message = function() end,
  on_message_appended = function(_, callback) appended = callback; return {} end
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
  Channel = { by_name = function() return channel end },
  register_command = function(name, callback) commands[name] = callback end
}

dofile("chatterino-plugin/init.lua")
commands["/overlay"]({ words = { "/overlay" }, channel = channel })
assert(type(appended) == "function", "Twitch listener was not attached")
appended({ id = "native-1", display_name = "Ana", message_text = "hola", username_color = "#112233" })
assert(#requests == 1, "native Twitch message was not published")
assert(requests[1].payload:find('"platform":"twitch"', 1, true), "wrong platform")
appended({ id = "kick-chat-1", display_name = "Bob", message_text = "duplicate" })
appended({ id = "yt-chat-1", display_name = "Cris", message_text = "duplicate" })
assert(#requests == 1, "plugin messages must not be duplicated")
io.open = original_open
print("bridge assertions: 4, failures: 0")
