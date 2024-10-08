local M = {}
---@type Mapper.Allmaps
M.maps = { i = {}, n = {}, x = {}, o = {}, t = {}, c = {}, r = {} }
M.condition = {
	always = function()
		return true
	end,
}
M.which_key_spec = {}
---@class Mapper.Config
---@field debug boolean
local cfg = { debug = false }

---@param user_config Mapper.Config
M.setup = function(user_config)
	cfg = vim.tbl_deep_extend("force", cfg, user_config) or cfg
end

local send_keys_to_nvim = function(string)
	local keys = vim.api.nvim_replace_termcodes(string, true, false, true)
	if vim.api.nvim_get_mode().mode == "niI" then
		return vim.cmd("normal " .. keys)
	end
	return vim.api.nvim_feedkeys(keys, "n", false)
end

local send_keys_to_nvim_with_count = function(string)
	local count = vim.api.nvim_get_vvar("count")
	send_keys_to_nvim((count ~= 0 and count or "") .. string)
end

---@param mode VimMode[]|VimMode: The mode or list of modes the mapping should apply to
---@param lhs string: left part of mapping
---@param rhs string|function Right part of mapping
---@param opts? Mapper.keymap: options for our keymap
M.map_keymap = function(mode, lhs, rhs, opts)
	---@type VimMode[]
	lhs = vim.fn.keytrans(vim.keycode(lhs))
	mode = type(mode) == "table" and mode or { mode }
	opts = opts or {}
	if type(rhs) == "function" then
		opts.callback = rhs
	elseif type(rhs) == "string" then
		opts.rhs = rhs
	else
		error("Unknown type of rhs")
	end
	if type(opts.condition) ~= "function" then
		error("Invalid condition for keymap")
	end
	opts.priority = opts.priority or 100
	for _, m in ipairs(mode) do
		if not M.maps[m][lhs] then
			M.maps[m][lhs] = {}
			local keymap_meta_info = vim.fn.maparg(lhs, m, nil, true)
			if vim.fn.len(keymap_meta_info) ~= 0 then
				if keymap_meta_info.buffer == 0 then
					M.maps[m][lhs][1] = vim.deepcopy(keymap_meta_info, true)
					M.maps[m][lhs][1].condition = M.condition.always
					M.maps[m][lhs][1].priority = 0
				end
			end
			M.setkeymap(m, lhs)
		end
		if not M.maps[m][lhs] then
			M.maps[m][lhs] = { opts }
			return true
		end
		for pos, keymap in ipairs(M.maps[m][lhs]) do
			if opts.priority > keymap.priority then
				table.insert(M.maps[m][lhs], pos, opts)
				return true
			end
		end
		table.insert(M.maps[m][lhs], opts)
		return true
	end
end

function M.setkeymap(m, lhs)
	table.insert(M.which_key_spec, {
		mode = m,
		lhs,
		function()
			for _, keymap in ipairs(M.maps[m][lhs]) do
				if keymap.condition() then
					if keymap.callback then
						return keymap.callback()
					elseif keymap.rhs then
						return send_keys_to_nvim_with_count(keymap.rhs)
					end
				end
			end
			send_keys_to_nvim_with_count(lhs)
		end,
		desc = function()
			for _, keymap in ipairs(M.maps[m][lhs]) do
				if keymap.condition() then
					return keymap.desc
				end
			end
			return nil
		end,
		icon = function()
			for _, keymap in ipairs(M.maps[m][lhs]) do
				if keymap.condition() then
					return keymap.icon
				end
			end
			return nil
		end,
	})
	vim.keymap.set(m, lhs, M.which_key_spec[#M.which_key_spec][2], { desc = "Mapper" })
	if package.loaded["which-key"] then
		require("which-key").add(M.which_key_spec)
	end
end

---@alias VimMode "n" | "v" | "i" | "x" | "s" | "t" | "c"
---@class Keymap
---@field[1]  VimMode[]|VimMode: mode
---@field[2] string: left
---@field[3] string | fun(fallback: unknown|nil) right
---@field[4] table?: opts: options for the specific keymap that override options passed through map_keymap_list
---@param mappings Keymap[]: A list of keymaps follwing the `Keymap` type
---@param ext_opts table: Options which will be additionally applied to every keymap in the given mapping list
M.map_keymap_list = function(mappings, ext_opts)
	---@param mapping Keymap
	vim.tbl_map(function(mapping)
		local mode = mapping[1]
		local left = mapping[2]
		local right = mapping[3]
		local opts = mapping[4]
		opts = vim.tbl_deep_extend("keep", opts or {}, ext_opts or {}) or {}
		M.map_keymap(mode, left, right, opts)
	end, mappings)
end

-- ---@param mode VimMode
-- ---@param left string
-- ---@param right string|fun(fallback: function|nil)
-- ---@param fallback boolean? Whether you want the fallback to be passed through. Needed when you are passing a callback with a different signature. For example, vim.lsp.buf.rename. True by default
-- M.gen_mapping = function(mode, left, right, fallback)
-- 	fallback = fallback == nil and true or fallback
-- 	if type(right) == "string" then
-- 		return function()
-- 			send_keys_to_nvim_with_count(right)
-- 		end
-- 	end
--
-- 	local mapping_or_default = function(mapping_callback)
-- 		return function()
-- 			local success, res = pcall(mapping_callback)
-- 			if not success then
-- 				if cfg.debug then
-- 					vim.notify(res, vim.log.levels.DEBUG)
-- 				end
-- 				return send_keys_to_nvim_with_count(left) -- send the raw keys back if we have not mapped the key
-- 			end
-- 			if type(res) == "string" then
-- 				send_keys_to_nvim_with_count(res)
-- 			end
-- 		end
-- 	end
--
-- 	if not fallback then
-- 		return mapping_or_default(right)
-- 	end
--
-- 	---@type string|function
-- 	local prev_mapping
-- 	local keymap_meta_info = vim.fn.maparg(left, mode, nil, true)
-- 	if vim.fn.len(keymap_meta_info) ~= 0 then
-- 		prev_mapping = keymap_meta_info.rhs or keymap_meta_info.callback
-- 	end
--
-- 	if not prev_mapping then
-- 		return mapping_or_default(right)
-- 	end
--
-- 	---@type function
-- 	prev_mapping = type(prev_mapping) == "function" and prev_mapping
-- 		or function()
-- 			send_keys_to_nvim_with_count(prev_mapping)
-- 		end
--
-- 	return mapping_or_default(function()
-- 		right(prev_mapping)
-- 	end)
-- end
--
return M
