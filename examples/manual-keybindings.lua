-- Manual keybindings example: Disable auto-keybindings and set up manually

local wezterm = require("wezterm")
local workspace_picker = wezterm.plugin.require("https://github.com/YOUR_USERNAME/workspace-picker.wezterm")

local config = wezterm.config_builder()

-- WezTerm configuration
config.color_scheme = "Tokyo Night"
config.font = wezterm.font("JetBrains Mono")

-- Setup workspace picker WITHOUT automatic keybindings
workspace_picker.setup({
	keybinds = nil, -- Disable automatic keybinding setup

	-- Still customize colors and zoxide path
	zoxide_path = "/opt/homebrew/bin/zoxide",
	colors = {
		workspace_prefix = "#9ece6a",
		zoxide_prefix = "#f7768e",
		current_indicator = "#9ece6a",
		text = "#c8d0e0",
		path = "#565f89",
	},
})

-- Manually define ALL keybindings
config.keys = {
	-- Use CMD+P for workspace picker (macOS style)
	{
		key = "p",
		mods = "CMD",
		action = wezterm.action_callback(function(win, pane)
			workspace_picker.show_workspace_selector(win, pane)
		end),
	},

	-- Use CMD+SHIFT+P for manual workspace creation
	{
		key = "P",
		mods = "CMD|SHIFT",
		action = workspace_picker.create_workspace_manually(),
	},

	-- Use CMD+R for renaming workspace
	{
		key = "r",
		mods = "CMD",
		action = workspace_picker.rename_workspace(),
	},

	-- Other custom keybindings
	{
		key = "t",
		mods = "CMD",
		action = wezterm.action.SpawnTab("CurrentPaneDomain"),
	},

	{
		key = "w",
		mods = "CMD",
		action = wezterm.action.CloseCurrentTab({ confirm = true }),
	},
}

return config
