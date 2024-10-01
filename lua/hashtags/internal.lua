local async = require('plenary.async')
local util = require('hashtags.util')
-- local await = async.await
-- local Job = require('plenary.job')

local globals = require('hashtags.globals')
local shown = false

--- @class DataEntry
--- @field file string File that contains the hashtag
--- @field mark_id number
--- @field lines table Context around the line containing the hashtag
--- @field from number Start column of the hashtag
--- @field to number End column of the hashtag
--- @field row number Line number of the hashtag
--- @field lastModifiedTime number

--- @class DataEntry2
--- @field hashtag string
--- @field mark_id number
--- @field row number
--- @field from number
--- @field to number
--- @field lines table

--- @class DataByFileEntry
--- @field hashtags DataEntry2[]
--- @field next_extmark_id number
--- @field lastModifiedTime number

--- @class EventArgs
--- @field buf number
--- @field event string
--- @field file string
--- @field group string
--- @field id number
--- @field match string

--- @class Internal
--- @field options Options|nil
--- @field root string|nil
--- @field data table|nil
local M = {
   options = nil,
   root = nil,

   --- @type table<string, DataEntry[]>
   data = nil,
   --- @type table<string, DataByFileEntry[]>
   data_by_file = nil,
}

--- Initialize the init_autocommands
--- @param extensions table Array of file extensions
local function init_autocommands(extensions)
   local augroup = vim.api.nvim_create_augroup('DAIC0R_HASHTAGS', { 
      clear = true
   })
   vim.api.nvim_create_autocmd({'BufReadPost'}, {
      group = augroup,
      --- @type fun(ev: EventArgs)
      callback = function(ev)
         if not M.data then
            return
         end
         if not vim.tbl_contains(extensions, ev.file:match('.+%.(%w+)$')) then
            return
         end
         if not M.data_by_file[ev.file] then
            --- TODO: Index the file
            return
         end
         local file_entry = M.data_by_file[ev.file]
         for _, hashtag in ipairs(file_entry.hashtags) do
            local mark_id = vim.api.nvim_buf_set_extmark(ev.buf, globals.HASHTAGS_HIGHLIGHT_NS, hashtag.row-1, hashtag.from-1, {
               virt_text = {{hashtag.hashtag, globals.HASHTAGS_MENU_HIGHLIGHT}},
               virt_text_pos = 'overlay',
               hl_mode = 'replace'
            })
            hashtag.mark_id = mark_id
            file_entry.next_extmark_id = file_entry.next_extmark_id + 1
         end
      end
   })
   vim.api.nvim_create_autocmd({'TextChanged'}, {
      group = augroup,
      --- @type fun(ev: EventArgs)
      callback = function(ev)
         -- For some reason here the absolute path is used,
         -- whereas above it isn't
         ev.file = ev.file:sub(#M.root + 2)
         local file_entry = M.data_by_file[ev.file]
         if not file_entry then
            return
         end
         for _, hashtag in ipairs(file_entry.hashtags) do
            if hashtag.mark_id then
               local ext_mark_item = vim.api.nvim_buf_get_extmark_by_id(ev.buf,
                  globals.HASHTAGS_HIGHLIGHT_NS,
                  hashtag.mark_id,
                  { details = false, hl_name = false }
               )
               hashtag.row = ext_mark_item[1] + 1
               hashtag.from = ext_mark_item[2] + 1
            end
         end
      end
   })
end

--- Initialize the internals
---
--- This function will try to find the root directory of the project and load the index file
--- @param opts Options
M.init = function(opts)
   M.root = M.find_root_dir(vim.fn.getcwd())
   if not M.root then
      return
   end
   M.options = opts
   local data = util.load_from_json(M.get_index_file())
   if data and #data == 2 then
      M.data = data[1]
      M.data_by_file = data[2]
   end
   local config = M.load_project_config()
   if not M.data then
      M.index_files(M.root, config.extensions)
   end
   init_autocommands(config.extensions)
end


--- Get the path to the file containing the index of hashtags
--- @return string Options that you want to override
M.get_index_file = function()
   return vim.fs.joinpath(M.root, '.hashtags.index.json')
end

--- Find the root directory of the project
--- @param path string
--- @return string|nil
M.find_root_dir = function(path)
   local found = vim.fs.find({'.git'}, { type = 'directory', path = path, upward = true, limit = 1 })
   if #found > 0 then
      return vim.fs.dirname(found[1])
   end
   return nil
end

--- Loads the project config file
--- @return table
M.load_project_config = function()
   local config_file = vim.fs.joinpath(M.root, '/.hashtags.json')
   local config = {}
   config = util.load_from_json(config_file) or { extensions = {} }
   return config
end

--- Index a file's hashtags
--- @param path string
--- @param filename string
M.index_file = function(path, filename)
   local tags = {}

   local f = io.open(filename, "r")
   if not f then
      return nil
   end
   local stat = vim.loop.fs_stat(filename)
   local content = f:read("*a")
   f:close()
   local lines = vim.split(content, '\n')

   filename = filename:sub(#path + 2) -- remove the root path including the slash
   for row, line in ipairs(lines) do
      local s, e = line:find('#[%u_]+')
      if s then
         local hashtag = line:sub(s, e)
         local ctx_lines = {}
         tags[hashtag] = tags[hashtag] or {}
         for i = row-M.options.context, row+M.options.context do
            if i < 1 or i > #lines then
               table.insert(ctx_lines, '')
            end
            table.insert(ctx_lines, lines[i])
         end
         table.insert(tags[hashtag],
            {file = filename, lines = ctx_lines, from = s, to = e,
               row = row, mark_id = nil, lastModifiedTime = stat.mtime.nsec })
      end
   end

   return filename, tags
end

--- Index files in a directory
--- @param path string
--- @param extensions table
--- @return table The indexed data
function M.index_files(path, extensions)
   return async.run(function()
      M.data = {}
      M.data_by_file = {}

      local files = vim.fs.find(function(name, path)
         -- #TODO make items ignorable
         if path:find('node_modules') or path:find('public') then
            return false
         end
         return vim.tbl_contains(extensions, name:match('.+%.(%w+)$'))
      end, { limit = math.huge, type = 'file', path = path})

      for _, filename in ipairs(files) do
         local stat = vim.loop.fs_stat(filename)

         local truncated_filename, tags = M.index_file(path, filename)

         if truncated_filename then
            for tag,entry_array in pairs(tags) do
               M.data[tag] = M.data[tag] or {}
               for _, entry in ipairs(entry_array) do
                  table.insert(M.data[tag], entry)
               end
            end

            M.data_by_file[truncated_filename] =
               M.data_by_file[truncated_filename] or
                  { hashtags = {}, next_extmark_id = 0, lastModifiedTime = stat.mtime.nsec }
            for tag,entry_array in pairs(tags) do
               for _, entry in ipairs(entry_array) do
                  table.insert(M.data_by_file[truncated_filename].hashtags, {
                     hashtag = tag,
                     row = entry.row,
                     from = entry.from,
                     to = entry.to,
                     lines = entry.lines,
                     mark_id = nil
                  })
               end
            end
         end
      end

      util.save_to_json(M.get_index_file(), M.data, M.data_by_file)
   end,
   function(data)
   end
   )
end

return M
