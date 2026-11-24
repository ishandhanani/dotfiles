-- Migrated from zellij (~/.config/zellij/config.kdl)

rex.action{
  name  = "then_normal",
  title = "Run an action and return to normal mode",
  args  = { action = "string", args = "object?" },
  run   = function(ctx, args)
    rex.client.queue(args.action, args.args or {})
    rex.client.queue("client.mode.exit_all")
  end,
}

-- zellij modes the user stays in are exclusive Rex modes
local modes = { "pane", "tab", "resize", "move", "tmux" } -- every mode except locked
rex.mode("locked", { exclusive = true })
for _, m in ipairs(modes) do
  rex.mode(m, { exclusive = true })
end

-- zellij's shared_except "locked": bind in normal mode and in every mode but `except`
local function shared(key, action, args, except)
  except = except or {}
  rex.bind(key, action, args)
  for _, m in ipairs(modes) do
    if not except[m] then
      rex.bind(m .. "/" .. key, action, args)
    end
  end
end

local function enter(name)
  return { name = name }
end

-- switching modes
shared("ctrl+g", "client.mode.enter", enter("locked"))
shared("ctrl+h", "client.mode.enter", enter("move"), { move = true })
shared("ctrl+b", "client.mode.enter", enter("tmux"), { tmux = true })
shared("ctrl+t", "client.mode.enter", enter("tab"), { tab = true })
shared("ctrl+p", "client.mode.enter", enter("pane"), { pane = true })
shared("ctrl+n", "client.mode.enter", enter("resize"), { resize = true })

-- leaving modes
rex.bind("locked/ctrl+g", "client.mode.exit_all")
rex.bind("pane/ctrl+p", "client.mode.exit_all")
rex.bind("tab/ctrl+t", "client.mode.exit_all")
rex.bind("resize/ctrl+n", "client.mode.exit_all")
rex.bind("move/ctrl+h", "client.mode.exit_all")
for _, m in ipairs(modes) do
  rex.bind(m .. "/enter", "client.mode.exit_all")
  rex.bind(m .. "/esc", "client.mode.exit_all")
end

-- alt bindings that work in every mode but locked
local dirs = { left = "left", down = "down", up = "up", right = "right", h = "left", j = "down", k = "up", l = "right" }
for key, dir in pairs({ left = "left", down = "down", up = "up", right = "right" }) do
  shared("alt+" .. key, "pane.focus", { direction = dir })
end
for key, dir in pairs({ h = "left", j = "down", k = "up", l = "right" }) do
  shared("alt+" .. key, "pane.focus", { direction = dir })
end
shared("alt+i", "client.tab.move", { direction = "backward" })
shared("alt+o", "client.tab.move", { direction = "forward" })
shared("alt+n", "pane.split", { direction = "auto" })

-- pane mode
for key, dir in pairs(dirs) do
  rex.bind("pane/" .. key, "pane.focus", { direction = dir })
end
rex.bind("pane/c", "then_normal", { action = "pane.rename" })
rex.bind("pane/d", "then_normal", { action = "pane.split", args = { direction = "down" } })
rex.bind("pane/f", "then_normal", { action = "pane.zoom" })
rex.bind("pane/n", "then_normal", { action = "pane.split", args = { direction = "auto" } })
rex.bind("pane/p", "pane.focus_next")
rex.bind("pane/r", "then_normal", { action = "pane.split", args = { direction = "right" } })
rex.bind("pane/x", "then_normal", { action = "pane.close" })

-- tab mode
local tabdirs = { left = "previous", down = "next", up = "previous", right = "next", h = "previous", j = "next", k = "previous", l = "next" }
for key, which in pairs(tabdirs) do
  rex.bind("tab/" .. key, "client.tab." .. which)
end
for i = 1, 9 do
  rex.bind("tab/" .. i, "then_normal", { action = "client.tab.goto", args = { index = i } })
end
rex.bind("tab/b", "then_normal", { action = "pane.move_to_new_tab" })
rex.bind("tab/n", "then_normal", { action = "client.tab.new" })
rex.bind("tab/r", "then_normal", { action = "client.tab.rename" })
rex.bind("tab/x", "then_normal", { action = "client.tab.close" })

-- resize mode
for key, dir in pairs(dirs) do
  rex.bind("resize/" .. key, "pane.resize", { direction = dir })
end

-- move mode
for key, dir in pairs(dirs) do
  rex.bind("move/" .. key, "pane.move", { direction = dir })
end

-- tmux mode
for key, dir in pairs(dirs) do
  rex.bind("tmux/" .. key, "then_normal", { action = "pane.focus", args = { direction = dir } })
end
rex.bind("tmux/shift+'", "then_normal", { action = "pane.split", args = { direction = "down" } })
rex.bind("tmux/shift+5", "then_normal", { action = "pane.split", args = { direction = "right" } })
rex.bind("tmux/,", "then_normal", { action = "client.tab.rename" })
rex.bind("tmux/ctrl+b", "then_normal", { action = "pane.send_key", args = { key = "ctrl+b" } })
rex.bind("tmux/c", "then_normal", { action = "client.tab.new" })
rex.bind("tmux/n", "then_normal", { action = "client.tab.next" })
rex.bind("tmux/o", "pane.focus_next")
rex.bind("tmux/p", "then_normal", { action = "client.tab.previous" })
rex.bind("tmux/x", "then_normal", { action = "pane.close" })
rex.bind("tmux/z", "then_normal", { action = "pane.zoom" })
