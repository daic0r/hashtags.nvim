local popup = require("plenary.popup")
local globals = require("hashtags.globals")
local internal = require("hashtags.internal")

--- UI module for hashtags.nvim
--- @class UI
--- @field bufnr number
--- @field win_id number
--- @field data table
--- @field cur_entry number
--- @field options Options
--- @field entry_size number
--- @field extmarks number[]
local M = {
}

M.init = function(opts)
   M.options = opts
   -- context lines above, context lines below + the line itself + the header
   M.entry_size = (M.options.context_top + 1 + M.options.context_bottom) + 1

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
      globals.HASHTAGS_MENU_FILENAME_SELECTED,
      opts.ui.theme.menu_filename_selected)
   vim.api.nvim_set_hl(globals.HASHTAGS_HIGHLIGHT_NS,
      globals.HASHTAGS_MENU_LINENUMBER_SELECTED,
      opts.ui.theme.menu_linenumber_selected)
   vim.api.nvim_set_hl(globals.HASHTAGS_HIGHLIGHT_NS,
      globals.HASHTAGS_MENU_CONTEXT_SELECTED,
      opts.ui.theme.menu_context_selected)

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
   tbl.extmarks = {}

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

--- @class ColRange
--- @field from number
--- @field to number

--- Highlights a line in the buffer
--- @param line number The line to highlight
--- @param ranges table<string, ColRange> A table with the column ranges to highlight
function M:highlight_buf_line(line, ranges)
   local line_array = vim.api.nvim_buf_get_lines(self.bufnr, line, line+1, false)
   if #line_array == 0 then
      return
   end

   local line_text = line_array[1]
   local max_to = -1
   for _, range in pairs(ranges) do
      max_to = math.max(max_to, range.to)
   end
   for hl_group, range in pairs(ranges) do
      local virt_text = line_text:sub(range.from, range.to)
      if range.to == max_to then
         virt_text = virt_text .. string.rep(' ', vim.api.nvim_win_get_width(self.win_id) - #virt_text)
      end
      --local virt_text = line_text .. string.rep(' ', vim.api.nvim_win_get_width(self.win_id) - #line_text)
      local opts = {
         virt_text = { { virt_text, hl_group } },
         virt_text_pos = 'overlay',  -- Make the virtual text overlay the line
         hl_eol = true
      }
      local mark_id = vim.api.nvim_buf_set_extmark(self.bufnr, globals.HASHTAGS_HIGHLIGHT_NS, line, range.from-1, opts)
      table.insert(self.extmarks, mark_id)
   end
   --vim.api.nvim_buf_add_highlight(self.bufnr, globals.HASHTAGS_HIGHLIGHT_NS, HASHTAGS_MENU_HIGHLIGHT, line, 0, #line_text)
   -- vim.api.nvim_buf_set_extmark(self.bufnr, globals.HASHTAGS_HIGHLIGHT_NS, line, 0, {
   --     virt_text = { { virt_text, globals.HASHTAGS_MENU_HIGHLIGHT } },
   --     virt_text_pos = 'overlay',  -- Make the virtual text overlay the line
   --  })
end

--- @param idx number index of the entry
--- @param selected boolean use selected or unselected colors
function M:color_entry(idx, selected)
   local lines = vim.api.nvim_buf_get_lines(self.bufnr, 0, -1, false)
   local begin_line = (idx-1) * self.entry_size + 1

   local filename_hl = selected and globals.HASHTAGS_MENU_FILENAME_SELECTED or globals.HASHTAGS_MENU_FILENAME
   local linenumber_hl = selected and globals.HASHTAGS_MENU_LINENUMBER_SELECTED or globals.HASHTAGS_MENU_LINENUMBER
   local context_hl = selected and globals.HASHTAGS_MENU_CONTEXT_SELECTED or globals.HASHTAGS_MENU_CONTEXT

   assert(filename_hl and linenumber_hl and context_hl)

   self:highlight_buf_line(begin_line-1, {
      [filename_hl] = { from = 1, to = lines[begin_line]:find(':') },
      [linenumber_hl] = { from = lines[begin_line]:find(':') + 1, to = #lines[begin_line] },
   })
   for i = 1, self.entry_size-1 do
      self:highlight_buf_line(begin_line-1+i, {
         [context_hl] = { from = 1, to = #lines[begin_line+i] },
      })
   end
end

--- Highlights the current entry
--- @param self UI
function M:highlight_cur_entry()
   for _, mark_id in ipairs(self.extmarks) do
      vim.api.nvim_buf_del_extmark(self.bufnr, globals.HASHTAGS_HIGHLIGHT_NS, mark_id)
   end
   self.extmarks = {}

   for i = 1, #self.data do
      self:color_entry(i, i == self.cur_entry+1)
   end

   vim.api.nvim_win_set_cursor(self.win_id, {self.cur_entry * self.entry_size + 1, 0})
end

--- Moves to the next entry
--- @param dir number The direction to move in
--- @param self UI
function M:next_entry(dir)
   self.cur_entry = (self.cur_entry + dir) % #self.data
   self:highlight_cur_entry()
end

--- Navigates to the selected entry
--- @param self UI
function M:do_nav()
   local entry = self.data[self.cur_entry + 1]
   local file = entry.file
   local cursor_pos = { entry.row, entry.from }
   vim.api.nvim_win_close(self.win_id, true)
   if entry.bufnr then
      vim.api.nvim_set_current_buf(entry.bufnr)
   elseif file then
      vim.api.nvim_command('e ' .. file)
   end
   vim.api.nvim_win_set_cursor(0, cursor_pos)
end

--- Shows the UI
--- @param data internal.DataEntry[]
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

   local current_buf = vim.api.nvim_get_current_buf()
   local this_file = internal.truncate_file_path(vim.api.nvim_buf_get_name(current_buf))
   local cursor_pos = vim.api.nvim_win_get_cursor(0)

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

   this.cur_entry = 0
   -- @type internal.DataEntry
   for idx, entry in ipairs(data) do
      this:add_entry(entry)

      if entry.file == this_file and entry.row == cursor_pos[1]
         and cursor_pos[2] >= entry.from-1 and cursor_pos[2] <= entry.to-1 then
            this.cur_entry = idx - 1
      end
   end

   this:highlight_cur_entry()

   vim.api.nvim_buf_set_option(bufnr, "modifiable", false)
   vim.api.nvim_buf_set_option(bufnr, "guicursor", "")
   vim.api.nvim_buf_set_option(bufnr, "buftype", "nofile")
end

return M
