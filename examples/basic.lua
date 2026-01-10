-- Basic example: Minimal setup with default settings

local wezterm = require("wezterm")
local workspace_picker = wezterm.plugin.require("https://github.com/YOUR_USERNAME/workspace-picker.wezterm")

local config = wezterm.config_builder()

-- Basic WezTerm configuration
config.color_scheme = "Tokyo Night"
config.font = wezterm.font("JetBrains Mono")

-- Set up LEADER key (required for default keybindings)
config.leader = { key = "Space", mods = "CTRL", timeout_milliseconds = 1000 }

-- Apply workspace picker with default settings
workspace_picker.apply_to_config(config)

return config
