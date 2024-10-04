local M = {}

M.HASHTAGS_AUGROUP = vim.api.nvim_create_augroup('daic0r.hashtags', {
   clear = true
})
M.HASHTAGS_HIGHLIGHT_NS = vim.api.nvim_create_namespace('daic0r.hashtags')
M.HASHTAGS_MENU_HIGHLIGHT = 'HashtagsMenu'
M.HASHTAGS_MENU_FILENAME = 'HashtagsMenuFilename'
M.HASHTAGS_MENU_LINENUMBER = 'HashtagsMenuLineNumber'
M.HASHTAGS_MENU_CONTEXT = 'HashtagsMenuContext'
M.HASHTAGS_BUFFER_MARKER = 'HashtagsBufferMarker'

return M
