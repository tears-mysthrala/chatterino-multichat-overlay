local function panel_name(ctx)
  local requested = tostring(ctx.words[2] or "")
  local panel = requested ~= "" and requested or tostring(ctx.channel:get_name() or "")
  panel = panel:lower():gsub("^%s+", ""):gsub("%s+$", "")
  if not panel:match("^[a-z0-9_%-]+$") then return nil end
  return panel
end

local function register()
  c2.register_command("/overlay", function(ctx)
    local panel = panel_name(ctx)
    if not panel then
      ctx.channel:add_system_message("Overlay: panel inválido. Uso: /overlay [panel]")
      return
    end
    ctx.channel:add_system_message("Overlay OBS: http://127.0.0.1:8765/overlay/" .. panel)
  end)
end

register()
