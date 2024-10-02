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
--- @field context number

--- @type Options
M = {
   context = 1,
   ui = {
      width = 90,
      height = 20,
      borderchars = { "─", "│", "─", "│", "╭", "╮", "╯", "╰" },
      border = true,
      theme = {
         menu_highlight = { fg = 'white', bg = 'blue' },
         menu_selected_highlight = { fg = 'blue', bg = 'white' },
         menu_filename = { fg = 'yellow', bg = 'blue' },
         menu_linenumber = { fg = 'green', bg = 'blue' },
         menu_context = { fg = 'grey', bg = 'blue' },
         buffer_marker = { fg = 'red', bg = 'blue' },
      },
   },
}

return M
