local M = {}

local popup = require("plenary.popup")

local ENTRY_HEIGHT = 2

local add_entry = function(buf, entry)
   local line1 = string.format("%s:%d", entry.file, entry.row, entry.line)
   local line2 = string.format("%s", entry.line)
   vim.api.nvim_buf_set_lines(buf, -1, -1, false, {line1, line2})
end

M.show_popup = function(data)
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

   vim.api.nvim_win_set_option(win_id, "number", false)

   local bufnr = vim.api.nvim_win_get_buf(win_id)
   vim.api.nvim_buf_set_lines(bufnr, -2, -1, false, {})
   vim.api.nvim_buf_set_keymap(bufnr, 'n', 'q', ':q<CR>', { noremap = true, silent = true })
   vim.api.nvim_buf_set_keymap(bufnr, 'n', 'j', ENTRY_HEIGHT .. 'j', { noremap = true, silent = true })
   vim.api.nvim_buf_set_keymap(bufnr, 'n', 'k', ENTRY_HEIGHT .. 'k', { noremap = true, silent = true })
   for _, entry in ipairs(data) do
      add_entry(bufnr, entry)
   end
end

return M
