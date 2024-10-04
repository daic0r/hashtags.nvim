local globals = require('hashtags.globals')

--- @class Theme
--- @field menu_filename table
--- @field menu_linenumber table
--- @field menu_context table
--- @field menu_filename_selected table
--- @field menu_linenumber_selected table
--- @field menu_context_selected table
--- @field buffer_marker table

--- @class UiOptions
--- @field width number
--- @field height number
--- @field borderchars table
--- @field border boolean
--- @field theme Theme

--- @class Options
--- @field ui UiOptions
--- @field context_top number
--- @field context_bottom number
--- @field refresh_timeout number
--- @field refresh_file_size_limit number

local sel_bg = vim.api.nvim_get_hl(0, { name = 'PmenuSel' }).bg
local title_fg = vim.api.nvim_get_hl(0, { name = 'Title' }).fg
local statusline_fg = vim.api.nvim_get_hl(0, { name = 'StatusLine' }).fg

--- @type Options
M = {
   context_top = 1,
   context_bottom = 2,
   refresh_timeout = 2000,
   refresh_file_size_limit = 1024 * 64,
   ui = {
      width = 90,
      height = 20,
      borderchars = { "─", "│", "─", "│", "╭", "╮", "╯", "╰" },
      border = true,
      theme = {
         menu_filename = { fg = title_fg, bg = 'none' },
         menu_linenumber = { fg = 'lightred', bg = 'none' },
         menu_context = { fg = statusline_fg, bg = 'none' },
         menu_filename_selected = { fg = title_fg, bg = sel_bg },
         menu_linenumber_selected = { fg = 'lightred', bg = sel_bg },
         menu_context_selected = { fg = statusline_fg, bg = sel_bg },
         buffer_marker = { fg = 'white', bg = 'teal' },
      },
   },
}

return M
