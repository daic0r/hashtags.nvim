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
         menu_highlight = { fg = 'White', bg = 'Blue' },
         menu_selected_highlight = { fg = 'Blue', bg = 'White' },
         menu_filename = { fg = 'Yellow', bg = 'Blue' },
         menu_linenumber = { fg = 'Green', bg = 'Blue' },
         menu_context = { fg = 'Grey', bg = 'Blue' },
      },
   },
}

return M
