local M = {
   bufnr = nil,
   win_id = nil,
}

M.new = function(bufnr, win_id)
   local tbl = {}
   tbl.bufnr = bufnr
   tbl.win_id = win_id
   setmetatable(tbl, { __index = M })
   return tbl
end

local popup = require("plenary.popup")

local ENTRY_HEIGHT = 2
local HASHTAGS_HIGHLIGHT_NS = vim.api.nvim_create_namespace('hashtags')
local HASHTAGS_MENU_HIGHLIGHT = 'HashtagsMenu'

local cur_entry = -1

vim.api.nvim_set_hl(HASHTAGS_HIGHLIGHT_NS, HASHTAGS_MENU_HIGHLIGHT, {  fg = "#ffffff", bg = "#005f87", bold = true })

function M:add_entry(entry)
   local line1 = string.format("%s:%d", entry.file, entry.row, entry.line)
   local line2 = string.format("%s", entry.line)
   local start = -1
   if #vim.api.nvim_buf_get_lines(self.bufnr, 0, -1, false) == 1 then
      start = 0
   end
   vim.api.nvim_buf_set_lines(self.bufnr, start, -1, false, {line1, line2})
end


function M:highlight_buf_line(line)
   local line_array = vim.api.nvim_buf_get_lines(self.bufnr, line, line+1, false)
   if #line_array == 0 then
      return
   end

   local line_text = line_array[1]
   local virt_text = line_text .. string.rep(' ', vim.api.nvim_win_get_width(self.win_id) - #line_text)
   vim.api.nvim_buf_set_extmark(self.bufnr, HASHTAGS_HIGHLIGHT_NS, line, 0, {
       virt_text = { { virt_text, HASHTAGS_MENU_HIGHLIGHT } },
       virt_text_pos = 'overlay',  -- Make the virtual text overlay the line
    })
end

function M:next_entry(dir)
   local lines = vim.api.nvim_buf_get_lines(self.bufnr, 0, -1, false)
   cur_entry = (cur_entry + dir) % (#lines / 2)
   vim.api.nvim_buf_clear_highlight(self.bufnr, HASHTAGS_HIGHLIGHT_NS, 0, -1)
   self:highlight_buf_line(cur_entry * 2)
   self:highlight_buf_line(cur_entry * 2 + 1)
end

M.show = function(data)
   local width = 90
   local height = 20
   local borderchars = { "─", "│", "─", "│", "╭", "╮", "╯", "╰" }
   local opts = {
      title = "Hashtags",
      line = math.floor((vim.o.lines - height) / 2),
      col = math.floor((vim.o.columns - width) / 2),
      minwidth = width,
      minheight = height,
      border = true,
      borderchars = borderchars,
   }
   print(opts.col)

   local win_id = popup.create({}, opts)
   vim.api.nvim_win_set_hl_ns(win_id, HASHTAGS_HIGHLIGHT_NS)

   vim.api.nvim_win_set_option(win_id, "number", false)

   local bufnr = vim.api.nvim_win_get_buf(win_id)

   local this = M.new(bufnr, win_id)

   vim.keymap.set('n', 'q', ':q<CR>', { buffer = bufnr, noremap = true, silent = true })
   vim.keymap.set('n', 'j', function() this:next_entry(1) end, { buffer = bufnr, noremap = true, silent = true })
   vim.keymap.set('n', 'k', function() this:next_entry(-1) end, { buffer = bufnr, noremap = true, silent = true })
   -- vim.api.nvim_buf_set_keymap(bufnr, 'n', 'q', ':q<CR>', { noremap = true, silent = true })
   -- vim.api.nvim_buf_set_keymap(bufnr, 'n', 'j', ':lua next_entry(' .. cur_entry .. ', 1)<CR>', { noremap = true, silent = true })
   -- vim.api.nvim_buf_set_keymap(bufnr, 'n', 'k', ':lua next_entry(' .. cur_entry .. ', -1)<CR>', { noremap = true, silent = true })
   for _, entry in ipairs(data) do
      this:add_entry(entry)
   end

   this:highlight_buf_line(0)
   this:highlight_buf_line(1)
end

return M
