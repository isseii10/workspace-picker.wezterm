-- Custom example: Full customization with theme and keybindings

local wezterm = require("wezterm")
local workspace_picker = wezterm.plugin.require("https://github.com/YOUR_USERNAME/workspace-picker.wezterm")

local config = wezterm.config_builder()

-- WezTerm configuration
config.color_scheme = "Catppuccin Mocha"
config.font = wezterm.font("JetBrains Mono", { weight = "Medium" })
config.font_size = 13.0
config.window_background_opacity = 0.95

-- Set up LEADER key
config.leader = { key = "Space", mods = "CTRL", timeout_milliseconds = 1000 }

-- Custom workspace picker setup with Catppuccin Mocha theme
workspace_picker.setup({
	-- Adjust zoxide path for your system
	zoxide_path = "/opt/homebrew/bin/zoxide",

	-- Catppuccin Mocha colors
	colors = {
		workspace_prefix = "#a6e3a1", -- Green
		zoxide_prefix = "#f38ba8", -- Red
		current_indicator = "#a6e3a1", -- Green
		text = "#cdd6f4", -- Text
		path = "#6c7086", -- Subtext
	},

	-- Custom keybindings
	keybinds = {
		show_picker = { mods = "LEADER", key = "w" }, -- Changed from 's' to 'w'
		create_workspace = { mods = "LEADER", key = "W" }, -- Shift+W
		rename_workspace = { mods = "LEADER", key = "R" }, -- Shift+R
	},
})

-- Apply to config
workspace_picker.apply_to_config(config)

-- Add status bar showing current workspace
wezterm.on("update-right-status", function(window, pane)
	local workspace = window:active_workspace()
	window:set_right_status(wezterm.format({
		{ Foreground = { Color = "#a6e3a1" } },
		{ Text = "  " .. workspace .. "  " },
	}))
end)

-- Additional keybindings (example)
table.insert(config.keys, {
	key = "t",
	mods = "LEADER",
	action = wezterm.action.SpawnTab("CurrentPaneDomain"),
})

table.insert(config.keys, {
	key = "x",
	mods = "LEADER",
	action = wezterm.action.CloseCurrentPane({ confirm = true }),
})

return config
