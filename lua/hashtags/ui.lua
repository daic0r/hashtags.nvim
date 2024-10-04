local popup = require("plenary.popup")
local globals = require("hashtags.globals")

--- UI module for hashtags.nvim
--- @class UI
--- @field bufnr number
--- @field win_id number
--- @field data table
--- @field cur_entry number
--- @field options Options
--- @field entry_size number
local M = {
}

M.init = function(opts)
   M.options = opts
   -- context lines above, context lines below + the line itself + the header
   M.entry_size = (M.options.context * 2 + 1) + 1

   vim.api.nvim_set_hl(globals.HASHTAGS_HIGHLIGHT_NS,
      globals.HASHTAGS_MENU_HIGHLIGHT,
      opts.ui.theme.menu_highlight)
   vim.api.nvim_set_hl(globals.HASHTAGS_HIGHLIGHT_NS,
      globals.HASHTAGS_MENU_FILENAME,
      opts.ui.theme.menu_filename)
   vim.api.nvim_set_hl(globals.HASHTAGS_HIGHLIGHT_NS,
      globals.HASHTAGS_MENU_LINENUMBER,
      opts.ui.theme.menu_linenumber)
   vim.api.nvim_set_hl(globals.HASHTAGS_HIGHLIGHT_NS,
      globals.HASHTAGS_MENU_CONTEXT,
      opts.ui.theme.menu_context)
   vim.api.nvim_set_hl(globals.HASHTAGS_HIGHLIGHT_NS,
      globals.HASHTAGS_BUFFER_MARKER,
      opts.ui.theme.buffer_marker)
end

local function new(bufnr, win_id, data)
   local tbl = {}
   tbl.bufnr = bufnr
   tbl.win_id = win_id
   tbl.data = data
   tbl.cur_entry = -1

   setmetatable(tbl, { __index = M })
   return tbl
end

function M:add_entry(entry)
   local filename = entry.file or vim.api.nvim_buf_get_name(entry.bufnr)
   local line1 = string.format("%s:%d", filename, entry.row, entry.line)
   local start = -1
   -- Account for initial empty line in buffer and overwrite it
   if #vim.api.nvim_buf_get_lines(self.bufnr, 0, -1, false) == 1 then
      start = 0
   end
   vim.api.nvim_buf_set_lines(self.bufnr, start, -1, false, {line1, unpack(entry.lines)})
end


function M:highlight_buf_line(line)
   local line_array = vim.api.nvim_buf_get_lines(self.bufnr, line, line+1, false)
   if #line_array == 0 then
      return
   end

   local line_text = line_array[1]
   local virt_text = line_text .. string.rep(' ', vim.api.nvim_win_get_width(self.win_id) - #line_text)
   --vim.api.nvim_buf_add_highlight(self.bufnr, globals.HASHTAGS_HIGHLIGHT_NS, HASHTAGS_MENU_HIGHLIGHT, line, 0, #line_text)
   vim.api.nvim_buf_set_extmark(self.bufnr, globals.HASHTAGS_HIGHLIGHT_NS, line, 0, {
       virt_text = { { virt_text, globals.HASHTAGS_MENU_HIGHLIGHT } },
       virt_text_pos = 'overlay',  -- Make the virtual text overlay the line
    })
end

function M:next_entry(dir)
   local lines = vim.api.nvim_buf_get_lines(self.bufnr, 0, -1, false)
   self.cur_entry = (self.cur_entry + dir) % (#lines / self.entry_size)
   vim.api.nvim_buf_clear_highlight(self.bufnr, globals.HASHTAGS_HIGHLIGHT_NS, 0, -1)
   for i = 0, self.entry_size-1 do
      self:highlight_buf_line(self.cur_entry * self.entry_size + i)
   end
   vim.api.nvim_win_set_cursor(self.win_id, {self.cur_entry * self.entry_size + 1, 0})
end

function M:do_nav()
   local entry = self.data[self.cur_entry + 1]
   local file = entry.file
   local cursor_pos = { entry.row, entry.from }
   vim.api.nvim_win_close(self.win_id, true)
   print(entry.bufnr)
   if entry.bufnr then
      vim.api.nvim_set_current_buf(entry.bufnr)
   elseif file then
      vim.api.nvim_command('e ' .. file)
   end
   vim.api.nvim_win_set_cursor(0, cursor_pos)
end

M.show = function(data)
   local opts = {
      title = "Hashtags",
      line = math.floor((vim.o.lines - M.options.ui.height) / 2),
      col = math.floor((vim.o.columns - M.options.ui.width) / 2),
      minwidth = M.options.ui.width,
      minheight = M.options.ui.height,
      border = M.options.ui.border,
      padding = { 0, 0, 1, 1 },
      borderchars = M.options.ui.borderchars,
   }

   local win_id = popup.create({}, opts)
   vim.api.nvim_win_set_hl_ns(win_id, globals.HASHTAGS_HIGHLIGHT_NS)
   vim.api.nvim_win_set_option(win_id, "number", false)

   local bufnr = vim.api.nvim_win_get_buf(win_id)

   local this = new(bufnr, win_id, data)

   vim.keymap.set('n', 'q', ':q<CR>', { buffer = bufnr, noremap = true, silent = true })
   vim.keymap.set('n', '<Esc>', ':q<CR>', { buffer = bufnr, noremap = true, silent = true })
   vim.keymap.set('n', 'j', function() this:next_entry(1) end, { buffer = bufnr, noremap = true, silent = true })
   vim.keymap.set('n', 'k', function() this:next_entry(-1) end, { buffer = bufnr, noremap = true, silent = true })
   vim.keymap.set('n', '<CR>', function() this:do_nav() end, { buffer = bufnr, noremap = true, silent = true })
   for _, entry in ipairs(data) do
      this:add_entry(entry)
   end

   this:next_entry(1)

   vim.api.nvim_buf_set_option(bufnr, "modifiable", false)
end

return M
