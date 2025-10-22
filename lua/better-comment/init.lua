local M = {}

local api = vim.api
local cmd = vim.api.nvim_create_autocmd
local treesitter = vim.treesitter

-- Create a single, reusable namespace ID for all highlights.
local NAMESPACE_ID = api.nvim_create_namespace("better_comments_ns")

-- Note: Background ('bg') and bold/underline are omitted if not specified,
-- allowing them to inherit the defaults (i.e., comment color).
local opts = {
	tags = {
		{
			name = "!",
			fg = "#ff2d00",
			bg = "",
			bold = true,
		},
		{
			name = "?",
			fg = "#1f98ff",
			bg = "",
			bold = true,
		},
		{
			name = "todo",
			fg = "#ff8c00",
			bg = "",
			bold = true,
		},
		{
			name = "TODO",
			fg = "#ff8c00",
			bg = "",
			bold = true,
		},
		{
			name = "*",
			fg = "#98C379",
			bg = "",
			bold = true,
		},
	},
}

-- Helper function to get the root of the Treesitter tree
local Get_root = function(bufnr, filetype)
	local parser = vim.treesitter.get_parser(bufnr, filetype, {})
	local tree = parser:parse()[1]
	return tree:root()
end

-- Helper function to create/update Neovim highlight groups
local function Create_hl(list)
	for id, hl in ipairs(list) do
		-- Use an ID derived from the list index as the highlight group name
		vim.api.nvim_set_hl(0, tostring(id), {
			fg = hl.fg,
			bg = hl.bg,
			bold = hl.bold,
			underline = hl.underline,
		})
	end
end

M.setup = function(config)
	-- Configuration logic (allows merging/overriding defaults)
	if config and config.default == false then
		opts.tags = {}
	end
	-- Use tbl_deep_extend to allow user config to override/add tags
	if config and config.tags then
		opts.tags = vim.tbl_deep_extend("force", opts.tags, config.tags or {})
	end

	local augroup = vim.api.nvim_create_augroup("better-comments", { clear = true })

	-- We run the update logic on relevant events
	cmd({ "BufWinEnter", "BufFilePost", "BufWritePost", "TextChanged", "TextChangedI" }, {
		group = augroup,
		callback = function()
			local current_buffer = api.nvim_get_current_buf()
			local current_buffer_name = api.nvim_buf_get_name(current_buffer)
			if current_buffer_name == "" then
				return
			end
			local fileType = api.nvim_buf_get_option(current_buffer, "filetype")

			-- Attempt to parse Treesitter query for comments
			local success, parsed_query = pcall(function()
				return treesitter.query.parse(fileType, [[(comment) @all]])
			end)

			-- 🐛 BUG FIX: Clear ALL previous highlights before doing anything else.
			api.nvim_buf_clear_namespace(current_buffer, NAMESPACE_ID, 0, -1)

			if not success or not parsed_query then
				return
			end

			-- Get all comments using Treesitter
			local root = Get_root(current_buffer, fileType)
			local comments = {}
			for _, node in parsed_query:iter_captures(root, current_buffer, 0, -1) do
				local range = { node:range() }
				table.insert(comments, {
					line = range[1],
					col_start = range[2],
					finish = range[4],
					text = vim.treesitter.get_node_text(node, current_buffer),
				})
			end

			if #comments == 0 then
				return
			end

			-- Create/ensure highlight groups exist
			Create_hl(opts.tags)

			-- Iterate over comments and apply highlights
			for id, comment in ipairs(comments) do
				for hl_id, hl in ipairs(opts.tags) do
					-- Check if the tag exists in the comment text
					if string.find(comment.text, hl.name, 1, true) then -- use 'true' for literal search
						local ns_id = NAMESPACE_ID

						-- Set Virtual Text (if defined)
						if hl.virtual_text and hl.virtual_text ~= "" then
							local v_opts = {
								id = comment.line,
								virt_text = { { hl.virtual_text, "" } },
								virt_text_pos = "overlay",
								virt_text_win_col = comment.finish + 2,
							}
							api.nvim_buf_set_extmark(current_buffer, ns_id, comment.line, 0, v_opts)
						end

						-- Set In-line Highlight
						vim.api.nvim_buf_add_highlight(
							current_buffer,
							ns_id,
							tostring(hl_id),
							comment.line,
							comment.col_start,
							comment.finish
						)

						-- Found a match, move to the next comment
						break
					end
				end
			end
		end,
	})
end

return M
