local internal = require('hashtags.internal')
local ui = require('hashtags.ui')
local default_options = require('hashtags.options')

local M = {}

local function nav_impl(direction)
   local cword = vim.fn.expand('<cWORD>')
   cword = cword:match('#[%u_]+')
   if not cword then
      return
   end

   internal.nav(cword, direction)
end

--- Jump to the next hashtag
M.nav_next = function()
   nav_impl(1)
end

--- Jump to the previous hashtag
M.nav_prev = function()
   nav_impl(-1)
end

--- Show the UI for the current hashtag
M.show_ui = function()
   local index = internal.data
   assert(index)

   local cword = vim.fn.expand('<cWORD>')
   cword = cword:match('#[%u_]+')
   if not cword or not index[cword] then
      return
   end
   ui.show(index[cword])
end


--- Setup the plugin
--- @param opts table Options that you want to override
M.setup = function(opts)
   local options = default_options
   if opts then
      options = vim.tbl_deep_extend("force", options, opts)
   end
   ui.init(options)
   internal.init(options)
end

return M
