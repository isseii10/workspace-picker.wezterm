---@class WorkspacePickerColors
---@field workspace_prefix string
---@field zoxide_prefix string
---@field current_indicator string
---@field text string
---@field path string

---@class WorkspacePickerKeybind
---@field mods string
---@field key string

---@class WorkspacePickerKeybinds
---@field show_picker WorkspacePickerKeybind?
---@field create_workspace WorkspacePickerKeybind?
---@field rename_workspace WorkspacePickerKeybind?

---@class WorkspacePickerLabels
---@field workspace string
---@field zoxide string
---@field current string

---@class WorkspacePickerConfig
---@field zoxide_path string
---@field colors WorkspacePickerColors
---@field labels WorkspacePickerLabels
---@field keybinds WorkspacePickerKeybinds|nil

local wezterm = require("wezterm")
local act = wezterm.action

local M = {}

-- Default configuration
---@type WorkspacePickerConfig
local default_config = {
	-- Path to zoxide command
	zoxide_path = "/opt/homebrew/bin/zoxide",
	-- Color settings
	colors = {
		workspace_prefix = "#9ece6a", -- Green
		zoxide_prefix = "#f7768e", -- Red
		current_indicator = "#9ece6a", -- Green
		text = "#c8d0e0", -- Light gray
		path = "#565f89", -- Dark gray
	},
	-- Label settings
	labels = {
		workspace = "[Workspace]",
		zoxide = "[Zoxide]",
		current = "<- current",
	},
	-- Keybind settings (set to nil to disable automatic setup)
	keybinds = {
		show_picker = { mods = "LEADER", key = "s" },
		create_workspace = { mods = "LEADER", key = "S" },
		rename_workspace = { mods = "LEADER", key = "r" },
	},
}

-- Store user configuration
---@type WorkspacePickerConfig|nil
local user_config

-- Merge configuration
---@param user_opts WorkspacePickerConfig|nil
---@return WorkspacePickerConfig
local function merge_config(user_opts)
	---@type WorkspacePickerConfig
	local config = {}
	for k, v in pairs(default_config) do
		if type(v) == "table" then
			config[k] = {}
			for tk, tv in pairs(v) do
				config[k][tk] = tv
			end
			if user_opts and user_opts[k] then
				for tk, tv in pairs(user_opts[k]) do
					config[k][tk] = tv
				end
			end
		else
			config[k] = v
		end
	end
	if user_opts then
		for k, v in pairs(user_opts) do
			if type(v) ~= "table" then
				config[k] = v
			end
		end
	end
	return config
end

-- Initialize configuration
---@param opts WorkspacePickerConfig|nil
---@return table
function M.setup(opts)
	user_config = merge_config(opts)
	return M
end

-- Get directory list from zoxide
---@return string[]
local function get_zoxide_directories()
	local config = user_config or default_config
	local zoxide_cmd = config.zoxide_path .. " query -l 2>/dev/null"

	local handle = io.popen(zoxide_cmd)
	if not handle then
		wezterm.log_warn("workspace-picker: Failed to execute zoxide command")
		return {}
	end

	local result = handle:read("*a")
	handle:close()

	local directories = {}
	for dir in result:gmatch("[^\r\n]+") do
		-- Replace home directory with ~
		local home = os.getenv("HOME")
		if home then
			dir = dir:gsub("^" .. home, "~")
		end
		table.insert(directories, dir)
	end

	return directories
end

-- Display workspace selector
---@param window any -- wezterm.Window
---@param pane any   -- wezterm.Pane
---@return nil
function M.show_workspace_selector(window, pane)
	local config = user_config or default_config
	local colors = config.colors
	local labels = config.labels
	local current = wezterm.mux.get_active_workspace()

	---@class WorkspacePickerChoice
	---@field id string
	---@field label string

	---@type WorkspacePickerChoice[]
	local choices = {}

	-- Add existing workspace list
	for _, name in ipairs(wezterm.mux.get_workspace_names()) do
		local label
		if current == name then
			label = wezterm.format({
				{ Foreground = { Color = colors.workspace_prefix } },
				{ Text = labels.workspace },
				{ Foreground = { Color = colors.text } },
				{ Text = string.format(" %-30s ", name) },
				{ Foreground = { Color = colors.current_indicator } },
				{ Text = labels.current },
			})
		else
			label = wezterm.format({
				{ Foreground = { Color = colors.workspace_prefix } },
				{ Text = labels.workspace },
				{ Foreground = { Color = colors.text } },
				{ Text = string.format(" %s ", name) },
			})
		end

		if name == "default" then
			-- Display default workspace at the top
			table.insert(choices, 1, {
				id = "ws:" .. name,
				label = label,
			})
		else
			table.insert(choices, {
				id = "ws:" .. name,
				label = label,
			})
		end
	end

	-- Get and add zoxide directory list
	local zoxide_dirs = get_zoxide_directories()
	if #zoxide_dirs > 0 then
		-- Add separator (only if zoxide directories exist)
		table.insert(choices, {
			id = "separator",
			label = "─────────────────────────────────────────────────────────",
		})

		for _, dir in ipairs(zoxide_dirs) do
			-- Get directory name (last path element)
			local dir_name = dir:match("([^/]+)$")
			local label = wezterm.format({
				{ Foreground = { Color = colors.zoxide_prefix } },
				{ Text = labels.zoxide },
				{ Foreground = { Color = colors.text } },
				{ Text = " " .. dir_name .. " " },
				{ Foreground = { Color = colors.path } },
				{ Text = "(" .. dir .. ")" },
			})
			table.insert(choices, {
				id = "zoxide:" .. dir,
				label = label,
			})
		end
	end

	-- Launch selection menu
	window:perform_action(
		act.InputSelector({
			action = wezterm.action_callback(function(win, p, id, label)
				if not id or id == "separator" then
					wezterm.log_info("Selection canceled or separator clicked")
					return
				end

				-- Branch processing based on id prefix
				if id:match("^ws:") then
					-- Switch to existing workspace
					local workspace_name = id:gsub("^ws:", "")
					win:perform_action(act.SwitchToWorkspace({ name = workspace_name }), p)
				elseif id:match("^zoxide:") then
					-- Create new workspace from zoxide directory
					local dir = id:gsub("^zoxide:", "")
					-- Convert ~ back to home directory
					local home = os.getenv("HOME")
					if home then
						dir = dir:gsub("^~", home)
					end

					local workspace_name = dir:match("([^/]+)$")
					win:perform_action(
						act.SwitchToWorkspace({
							name = workspace_name,
							spawn = {
								cwd = dir,
							},
						}),
						p
					)
				end
			end),
			title = "(wezterm) Select workspace",
			choices = choices,
			alphabet = "", -- Disable character key search (j/k can be used for navigation)
			description = "(wezterm) Select workspace or directory: ['/': search]",
			fuzzy_description = "(wezterm) Select workspace or directory: ",
		}),
		pane
	)
end

-- Rename workspace
---@return any -- wezterm.Action
function M.rename_workspace()
	return act.PromptInputLine({
		description = "(wezterm) Rename workspace title: ",
		action = wezterm.action_callback(function(win, pane, line)
			if line then
				wezterm.mux.rename_workspace(wezterm.mux.get_active_workspace(), line)
			end
		end),
	})
end

-- Create new workspace manually
---@return any -- wezterm.Action
function M.create_workspace_manually()
	return act.PromptInputLine({
		description = "(wezterm) Create new workspace: ",
		action = wezterm.action_callback(function(window, pane, line)
			if line then
				window:perform_action(
					act.SwitchToWorkspace({
						name = line,
					}),
					pane
				)
			end
		end),
	})
end

-- Add keybindings to config
---@param config table
---@param opts WorkspacePickerConfig|nil
---@return table
function M.apply_to_config(config, opts)
	-- Merge config (use opts if provided)
	local cfg = opts and merge_config(opts) or (user_config or default_config)

	-- Use existing keys table if available, otherwise create new one
	if not config.keys then
		config.keys = {}
	end

	-- Only add keybindings if configured
	if cfg.keybinds then
		if cfg.keybinds.show_picker then
			table.insert(config.keys, {
				mods = cfg.keybinds.show_picker.mods,
				key = cfg.keybinds.show_picker.key,
				action = wezterm.action_callback(function(win, pane)
					M.show_workspace_selector(win, pane)
				end),
			})
		end

		if cfg.keybinds.create_workspace then
			table.insert(config.keys, {
				mods = cfg.keybinds.create_workspace.mods,
				key = cfg.keybinds.create_workspace.key,
				action = M.create_workspace_manually(),
			})
		end

		if cfg.keybinds.rename_workspace then
			table.insert(config.keys, {
				mods = cfg.keybinds.rename_workspace.mods,
				key = cfg.keybinds.rename_workspace.key,
				action = M.rename_workspace(),
			})
		end
	end

	return config
end

return M
