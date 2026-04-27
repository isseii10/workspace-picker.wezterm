---@class WorkspacePickerColors
---@field workspace_prefix string
---@field zoxide_prefix string
---@field current_indicator string
---@field text string
---@field path string

---@class WorkspacePickerKeybind
---@field mods string
---@field key string

---@class WorkspacePickerConfig
---@field zoxide_path string
---@field colors WorkspacePickerColors
---@field labels WorkspacePickerLabels
---@field activate_keytable WorkspacePickerKeybind?

local wezterm = require("wezterm")
local act = wezterm.action

local M = {}

-- Get the data directory path following XDG spec
---@return string
local function get_data_dir()
	local data_dir

	-- Check if running on macOS
	local handle = io.popen("uname -s")
	local uname = handle and handle:read("*a") or ""
	if handle then handle:close() end
	local is_macos = uname:match("Darwin")

	if is_macos then
		-- On macOS, force use default Linux path
		local home = os.getenv("HOME")
		data_dir = home and home .. "/.local/share/workspace-picker" or nil
	else
		-- On Linux, use XDG_DATA_HOME if set
		local xdg_data = os.getenv("XDG_DATA_HOME")
		if xdg_data then
			data_dir = xdg_data .. "/workspace-picker"
		else
			local home = os.getenv("HOME")
			data_dir = home and home .. "/.local/share/workspace-picker" or nil
		end
	end

	return data_dir or ""
end

-- Ensure data directory exists
---@return boolean
local function ensure_data_dir()
	local data_dir = get_data_dir()
	if data_dir == "" then
		return false
	end

	local cmd = string.format("mkdir -p %s 2>/dev/null", data_dir)
	local handle = io.popen(cmd)
	if handle then
		handle:close()
		return true
	end
	return false
end

-- Save workspace state to file
---@param workspace_name string
---@param state table|nil
---@return boolean
local function save_workspace_state(workspace_name, state)
	if not ensure_data_dir() then
		return false
	end

	local data_dir = get_data_dir()
	local file_path = data_dir .. "/" .. workspace_name .. ".json"

	local file = io.open(file_path, "w")
	if not file then
		return false
	end

	local json_state = require("json")
	local ok, json_str = pcall(json_state.encode, state or {})
	if not ok then
		file:close()
		return false
	end

	file:write(json_str)
	file:close()
	return true
end

-- Load workspace state from file
---@param workspace_name string
---@return table|nil
local function load_workspace_state(workspace_name)
	local data_dir = get_data_dir()
	if data_dir == "" then
		return nil
	end

	local file_path = data_dir .. "/" .. workspace_name .. ".json"
	local file = io.open(file_path, "r")
	if not file then
		return nil
	end

	local content = file:read("*a")
	file:close()

	if content == "" then
		return nil
	end

	local json_state = require("json")
	local ok, state = pcall(json_state.decode, content)
	if not ok then
		return nil
	end

	return state
end

-- Delete workspace state file
---@param workspace_name string
---@return boolean
local function delete_workspace_state(workspace_name)
	local data_dir = get_data_dir()
	if data_dir == "" then
		return false
	end

	local file_path = data_dir .. "/" .. workspace_name .. ".json"
	local cmd = string.format("rm -f %s", file_path)
	local handle = io.popen(cmd)
	if handle then
		handle:close()
		return true
	end
	return false
end

-- Get list of saved workspaces
---@return string[]
local function get_saved_workspaces()
	local data_dir = get_data_dir()
	if data_dir == "" then
		return {}
	end

	local cmd = string.format("ls -1 %s/*.json 2>/dev/null | xargs -n1 basename 2>/dev/null", data_dir)
	local handle = io.popen(cmd)
	if not handle then
		return {}
	end

	local result = handle:read("*a")
	handle:close()

	local workspaces = {}
	for file in result:gmatch("[^\r\n]+") do
		local ws_name = file:match("^(.+)%.json$")
		if ws_name then
			table.insert(workspaces, ws_name)
		end
	end

	return workspaces
end

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
	-- Keybind to activate workspace keytable (set to nil to disable)
	activate_keytable = { mods = "LEADER", key = "w" },
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
			if type(v) == "table" then
				for tk, tv in pairs(v) do
					config[k][tk] = tv
				end
			else
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
	for d in result:gmatch("[^\r\n]+") do
		-- Replace home directory with ~
		local home = os.getenv("HOME")
		local normalized_d = d
		if home then
			normalized_d = d:gsub("^" .. home, "~")
		end
		table.insert(directories, normalized_d)
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

-- Save current workspace state
---@return any -- wezterm.Action
function M.save_workspace()
	return act.PromptInputLine({
		description = "(wezterm) Save workspace as: ",
		action = wezterm.action_callback(function(win, pane, line)
			if line then
				local state = {
					name = wezterm.mux.get_active_workspace(),
					timestamp = os.time(),
				}
				local ok = save_workspace_state(line, state)
				if ok then
					wezterm.log_info("workspace-picker: Saved workspace as '" .. line .. "'")
				else
					wezterm.log_warn("workspace-picker: Failed to save workspace '" .. line .. "'")
				end
			end
		end),
	})
end

-- Show restore workspace menu
---@param window any -- wezterm.Window
---@param pane any   -- wezterm.Pane
---@return nil
function M.show_restore_menu(window, pane)
	local saved = get_saved_workspaces()

	if #saved == 0 then
		window:perform_action(
			act.Notification({
				title = "No Saved Workspaces",
				body = "No saved workspaces found. Use Leader+W to save one.",
			}),
			pane
		)
		return
	end

	---@class WorkspacePickerRestoreChoice
	---@field id string
	---@field label string

	---@type WorkspacePickerRestoreChoice[]
	local choices = {}

	for _, name in ipairs(saved) do
		local state = load_workspace_state(name)
		local timestamp = state and state.timestamp or 0
		local date = os.date("%Y-%m-%d %H:%M", timestamp)

		local label = wezterm.format({
			{ Text = string.format(" %s ", name) },
			{ Foreground = { Color = "#565f89" } },
			{ Text = "(" .. date .. ")" },
		})

		table.insert(choices, {
			id = "restore:" .. name,
			label = label,
		})
	end

	window:perform_action(
		act.InputSelector({
			action = wezterm.action_callback(function(win, p, id, label)
				if not id then
					return
				end

				local workspace_name = id:gsub("^restore:", "")
				local state = load_workspace_state(workspace_name)

				if state then
					win:perform_action(
						act.SwitchToWorkspace({
							name = workspace_name,
						}),
						p
					)
					wezterm.log_info("workspace-picker: Restored workspace '" .. workspace_name .. "'")
				else
					wezterm.log_warn("workspace-picker: Failed to load workspace state for '" .. workspace_name .. "'")
				end
			end),
			title = "(wezterm) Restore workspace",
			choices = choices,
			alphabet = "",
			description = "(wezterm) Restore a saved workspace: ",
			fuzzy_description = "(wezterm) Restore workspace: ",
		}),
		pane
	)
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

	-- Define the workspace keytable
	config.key_tables = config.key_tables or {}
	config.key_tables["workspace_picker"] = {
		-- Show workspace selector
		{ key = "w", action = wezterm.action_callback(function(win, pane)
			M.show_workspace_selector(win, pane)
		end) },

		-- Create workspace
		{ key = "c", action = M.create_workspace_manually() },

		-- Rename workspace
		{ key = "e", action = M.rename_workspace() },

		-- Save workspace (auto-pop keytable after)
		{ key = "s", action = wezterm.action_callback(function(win, pane)
			local name = wezterm.mux.get_active_workspace()
			local state = {
				name = name,
				timestamp = os.time(),
			}
			local ok = save_workspace_state(name, state)
			if ok then
				wezterm.log_info("workspace-picker: Saved workspace '" .. name .. "'")
			else
				wezterm.log_warn("workspace-picker: Failed to save workspace '" .. name .. "'")
			end
			win:perform_action("PopKeyTable", pane)
		end) },

		-- Restore workspace
		{ key = "r", action = wezterm.action_callback(function(win, pane)
			M.show_restore_menu(win, pane)
		end) },

		-- Quit keytable
		{ key = "q", action = "PopKeyTable" },
		{ key = "Escape", action = "PopKeyTable" },
	}

	-- Activate keytable
	if cfg.activate_keytable then
		table.insert(config.keys, {
			mods = cfg.activate_keytable.mods,
			key = cfg.activate_keytable.key,
			action = act.ActivateKeyTable({
				name = "workspace_picker",
				one_shot = false,
			}),
		})
	end

	return config
end

-- Get data directory (for external use)
function M.get_data_dir()
	return get_data_dir()
end

-- Delete a saved workspace
---@param workspace_name string
---@return boolean
function M.delete_workspace(workspace_name)
	return delete_workspace_state(workspace_name)
end

-- Get list of saved workspaces
---@return string[]
function M.get_saved_workspaces()
	return get_saved_workspaces()
end

-- Load workspace state
---@param workspace_name string
---@return table|nil
function M.load_workspace(workspace_name)
	return load_workspace_state(workspace_name)
end

return M
