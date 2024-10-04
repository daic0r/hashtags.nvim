local M = {}

M.HASHTAGS_AUGROUP = vim.api.nvim_create_augroup('daic0r.hashtags', {
   clear = true
})
M.HASHTAGS_HIGHLIGHT_NS = vim.api.nvim_create_namespace('daic0r.hashtags')

M.HASHTAGS_MENU_FILENAME = 'HashtagsMenuFilename'
M.HASHTAGS_MENU_LINENUMBER = 'HashtagsMenuLineNumber'
M.HASHTAGS_MENU_CONTEXT = 'HashtagsMenuContext'
M.HASHTAGS_MENU_FILENAME_SELECTED= 'HashtagsMenuFilenameSelected'
M.HASHTAGS_MENU_LINENUMBER_SELECTED = 'HashtagsMenuLineNumberSelected'
M.HASHTAGS_MENU_CONTEXT_SELECTED = 'HashtagsMenuContextSelected'

M.HASHTAGS_BUFFER_MARKER = 'HashtagsBufferMarker'
M.COMMAND_PREFIX = 'Hashtags'

return M
