--- @class Theme
--- @field menu_highlight table
--- @field menu_selected_highlight table 
--- @field menu_filename table
--- @field menu_linenumber table
--- @field menu_context table

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
         menu_highlight = { fg = 'white', bg = 'blue' },
         menu_selected_highlight = { fg = 'blue', bg = 'white' },
         menu_filename = { fg = 'yellow', bg = 'blue' },
         menu_linenumber = { fg = 'red', bg = 'blue' },
         menu_context = { fg = 'lightgreen', bg = 'blue' },
         buffer_marker = { fg = 'white', bg = 'teal' },
      },
   },
}

return M
