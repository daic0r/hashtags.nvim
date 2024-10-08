# hashtags.nvim

> [!WARNING]
> DISCLAIMER: this is new and might very well be buggy!
> 
> Contributions welcome :-)

This plugin enables you to place _#HASHTAGS_ in your files between which you can then navigate via
- a menu
- keyboard shortcuts

![menu_screenshot_blank](https://github.com/user-attachments/assets/4e8a432a-80cd-4581-be66-11162d6a0f3a)

## Installation and configuration:

### lazy.nvim:

```lua
{
   'daic0r/hashtags.nvim',
   dependencies = { "nvim-lua/plenary.nvim" },
   config = function()
      local hashtags = require('hashtags')
      hashtags.setup()
      vim.keymap.set('n', '<leader>hn', hashtags.nav_next)
      vim.keymap.set('n', '<leader>hp', hashtags.nav_prev)
      vim.keymap.set('n', '<leader>hs', hashtags.show_ui)
   end
}
```

This will set up the plugin with the default options. See below for more information.

## Documentation:

First a definition: a _#hashtag_ is a `#` followed by any number of uppercase letters and underscores.

In the configuration above you can see the 4 user-facing functions `setup(opts)`, `nav_next`, `nav_prev` and `show_ui`.
All of them require the cursor to be on a hashtag for context.

- `setup(opts)`: Set up the plugin with the options passed in `opts`
- `nav_next`: Navigate to the next location of the hashtag the cursor is currently placed on
- `nav_prev`: Navigate to the previous location of the hashtag the cursor is currently placed on
- `show_ui`: Pull up the UI, giving you an overview of all the locations that were registered for this hashtag

Furthermore, the following user commands are registered:

- `:HashtagsReparse`: reparse the current buffer and highlight all hashtags
- `:HashtagsRegenIndex`: regenerate index and rewrite index file
- `:HashtagsGenConfig`: generate an example config file in the project root directory

The "index" is a cache of all the hashtags that were found in the workspace and saved in the root of the workspace.
The index file is called `.hashtags.index.json`.

The root directory of the workspace is determined by the location of `.git`.
> [!NOTE]
> A `.git` directory is required for this plugin to work

The config file is called `.hashtags.config.json` and contains 2 arrays:
- `include`: glob pattern to specify which files should be parsed for hashtags
- `exclude`: files/directories to ignore

### Options

The following default options will be set if you don't override them:

```lua
local sel_bg = vim.api.nvim_get_hl(0, { name = 'PmenuSel' }).bg
local title_fg = vim.api.nvim_get_hl(0, { name = 'Title' }).fg
local statusline_fg = vim.api.nvim_get_hl(0, { name = 'StatusLine' }).fg

{
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
```

### Option breakdown

- `context_top`: number of lines displayed above the line containing the hashtag in the menu
- `context_bottom`: number of lines displayed below the line containing the hashtag in the menu
- `refresh_timeout`: number of milliseconds to wait before the buffer is rescanned after editing it (`nil` for never)
- `refresh_file_size_limit`: files larger than this will not be automatically rescanned

#### UI

See the image below to learn what parts of the UI the theme options refer to (the `_selected` parts refer to the currently selected menu item):

![menu_screenshot](https://github.com/user-attachments/assets/69b9049b-473e-48cc-81fc-72b7f20af489)

## Ideas for possible further improvement

- [ ] Integration with quickfix list
- [ ] Generate global marks
