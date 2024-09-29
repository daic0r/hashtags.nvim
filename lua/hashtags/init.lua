local M = {}

local utils = require('hashtags.utils')
local ui = require('hashtags.ui')

-- #BRUHfafjsdjf
-- #HERE

M.nav_next = function()
   local index = utils.data
   local cword = vim.fn.expand('<cWORD>')
   cword = cword:match('#[%u_]+')
   if not index[cword] then
      return
   end
   local current = vim.api.nvim_get_current_buf()
   local this_file = vim.api.nvim_buf_get_name(current)
   local cursor_pos = vim.api.nvim_win_get_cursor(0)
   local next_idx = 0
   for idx, entry in ipairs(index[cword]) do
      print("have " .. #index[cword] .. " entries")
      if entry.file == this_file and entry.row == cursor_pos[1] and cursor_pos[2] >= entry.from and cursor_pos[2] <= entry.to then
         next_idx = (idx % #index[cword]) + 1
         print("Found at " .. idx .. " next is " .. next_idx)
         break
      end
   end
   if next_idx == 0 then
      return
   end
   print("Next idx: " .. next_idx)
   local next = index[cword][next_idx]
   print("Going to " .. next.file .. " at " .. next.row .. ":" .. next.from)
   if next then
      vim.api.nvim_command('e ' .. next.file)
      vim.api.nvim_win_set_cursor(0, {next.row, next.from})
   end
   -- table.insert
   -- local bufs = vim.api.nvim_list_bufs()
   -- for _, buf in ipairs(bufs) do
   --    if vim.api.nvim_buf_is_loaded(buf) then
   --       local
   --    end
   -- end
end

M.show_marks = function()
   local index = utils.data
   local cword = vim.fn.expand('<cWORD>')
   cword = cword:match('#[%u_]+')
   if not index[cword] then
      return
   end
   ui.show(index[cword])
end

M.setup = function()
   utils.init()
end

package.loaded['hashtags.utils'] = nil
package.loaded['hashtags.ui'] = nil
package.loaded['hashtags'] = nil

return M
