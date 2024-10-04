local async = require('plenary.async')
local util = require('hashtags.util')
-- local await = async.await
-- local Job = require('plenary.job')

local globals = require('hashtags.globals')
local shown = false

--- @class DataEntry
--- @field file string File that contains the hashtag
--- @field bufnr number|nil Buffer number of the file
--- @field lastModifiedTime number
--- @field mark_id number
--- @field lines table Context around the line containing the hashtag
--- @field from number Start column of the hashtag
--- @field to number End column of the hashtag
--- @field row number Line number of the hashtag

--- @class DataEntry2
--- @field hashtag string
--- @field mark_id number
--- @field lines table
--- @field from number
--- @field to number
--- @field row number

--- @class DataByFileEntry
--- @field hashtags DataEntry2[]
--- @field next_extmark_id number
--- @field lastModifiedTime number|nil
--- @field bufnr number|nil

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
   --- @type table<string|number, DataByFileEntry>
   data_by_file = nil,
}

--- @type table<number, uv_timer_t>
local buffer_timers = {}

--- Parse a line for a hashtag
--- @param line string # Line to parse
--- @return table[] Array of hashtags and their positions
local function parse_line(line)
   local ret = {}
   for hashtag in line:gmatch('#[%u_]+') do
      table.insert(ret, { hashtag = hashtag, from = line:find(hashtag) })
   end
   return ret
end

--- Check if index has a particular hashtag instance
--- @param hashtag_index table Array of hashtag instances for this particular hashtag (shoul be M.data[hashtag])
--- @param hashtag_instance table Hashtag instance to check for
local function has_buffer_hashtag_instance(hashtag_index, hashtag_instance)
   if not hashtag_index then
      return false
   end
   for _, hashtag in ipairs(hashtag_index) do
      if hashtag_instance.row == hashtag.row and
         hashtag_instance.from == hashtag.from then
         return true
      end
   end
   return false
end

--- Get the context lines around a row
--- @param lines table Array of lines
--- @param row number Row to get context around
--- @param context number Number of lines to get around the row
local function get_context_lines(lines, row, context)
   local ctx_lines = {}
   for i = row-context, row+context do
      if i < 1 or i > #lines then
         table.insert(ctx_lines, '')
      end
      table.insert(ctx_lines, lines[i])
   end
   return ctx_lines
end

--- Clear the data for a file or buffer
--- @param file_or_buf string|number
local function clear_data_for_file_or_buf(file_or_buf)
   local file = file_or_buf
   if type(file_or_buf) == 'number' then
      file = vim.api.nvim_buf_get_name(file_or_buf)
   end
   M.data_by_file[file] = nil
   for hashtag, entries in pairs(M.data) do
      M.data[hashtag] = vim.tbl_filter(function(entry)
         return entry.file ~= file
      end, entries)
   end
end

--- Create extmarks for a buffer
--- @param bufnr number
--- @param tags table
--- @param on_create_func fun(hashtag: DataEntry2, mark_id: number)
local function create_extmarks(bufnr, tags, on_create_func)
   vim.api.nvim_set_hl_ns(globals.HASHTAGS_HIGHLIGHT_NS)
   for _, hashtag in ipairs(tags) do
      local mark_id = vim.api.nvim_buf_set_extmark(bufnr, globals.HASHTAGS_HIGHLIGHT_NS, hashtag.row-1, hashtag.from-1, {
         virt_text = {{hashtag.hashtag, globals.HASHTAGS_BUFFER_MARKER}},
         virt_text_pos = 'overlay',
      })
      print("Set it")
      on_create_func(hashtag, mark_id)
   end
end

--- Index a buffer's hashtags
--- @param file_or_buf table
--- @param lines table
--- @return table
local function index_buffer(file_or_buf, lines)
   local tags = {}
   local stat = type(file_or_buf)=="string" and vim.loop.fs_stat(file_or_buf)
   for row, line in ipairs(lines) do
      local hashtags = parse_line(line)
      for _,entry in ipairs(hashtags) do
         local hashtag = entry.hashtag
         local ctx_lines = {}
         tags[hashtag] = tags[hashtag] or {}
         for i = row-M.options.context, row+M.options.context do
            if i < 1 or i > #lines then
               table.insert(ctx_lines, '')
            end
            table.insert(ctx_lines, lines[i])
         end
         table.insert(tags[hashtag],
            {file = file_or_buf.file,
               bufnr = file_or_buf.bufnr,
               lines = ctx_lines, from = entry.from, to = entry.from + #hashtag,
               row = row, mark_id = nil, lastModifiedTime = stat and stat.mtime.nsec })
      end
   end
   return tags
end

--- Initialize the init_autocommands
local function init_autocommands()
   -- #TODO: new file is created, add it to the index
   -- #TODO: file is being edited, check for new hashtags
   vim.api.nvim_create_autocmd({'BufReadPost'}, {
      group = globals.HASHTAGS_AUGROUP,
      --- @type fun(ev: EventArgs)
      callback = function(ev)
         if not M.data then
            return
         end
         if not M.data_by_file[ev.file] and not M.data_by_file[ev.buf] then
            return
         end
         local file_entry = M.data_by_file[ev.file] or M.data_by_file[ev.buf]
         file_entry.bufnr = ev.buf

         create_extmarks(ev.buf, file_entry.hashtags, function(hashtag, mark_id)
            hashtag.mark_id = mark_id
            file_entry.next_extmark_id = file_entry.next_extmark_id + 1
            --
            -- Sync with other map
            local hashtag_entry = vim.tbl_filter(function(entry)
               return entry.file == ev.file and entry.row == hashtag.row and entry.from == hashtag.from
            end, M.data[hashtag.hashtag])
            if #hashtag_entry == 1 then
               hashtag_entry[1].mark_id = mark_id
               hashtag_entry[1].bufnr = ev.buf
            end
         end)
      end
   })
   vim.api.nvim_create_autocmd({'TextChanged', 'TextChangedI'}, {
      group = globals.HASHTAGS_AUGROUP,
      --- @type fun(ev: EventArgs)
      callback = function(ev)
         local buf_timer = nil
         if M.options.refresh_timeout then
            buf_timer = buffer_timers[ev.buf]
            if not buf_timer then
               buffer_timers[ev.buf] = vim.loop.new_timer()
               buf_timer = buffer_timers[ev.buf]
            end
            if buf_timer:is_active() then
               buf_timer:stop()
            end
         end

         -- For some reason here the absolute path is used,
         -- whereas above it isn't
         ev.file = M.truncate_file_path(ev.file)

         --- @type DataByFileEntry
         local file_entry = M.data_by_file[ev.file]
         if not file_entry then
            return
         end

         -- No timeout given -> let's update the positions at least
         if not M.options.refresh_timeout then
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
            return
         else
            buf_timer:start(M.options.refresh_timeout, 0, vim.schedule_wrap(function()
               vim.api.nvim_buf_clear_namespace(ev.buf, globals.HASHTAGS_HIGHLIGHT_NS, 0, -1)

               local tags = index_buffer({ file = ev.file, bufnr = ev.buf }, vim.api.nvim_buf_get_lines(ev.buf, 0, -1, false))
               M.merge_tags(ev.file, tags)

               create_extmarks(ev.buf, M.data_by_file[ev.file].hashtags, function(hashtag, mark_id)
                  hashtag.mark_id = mark_id
                  file_entry.next_extmark_id = file_entry.next_extmark_id + 1
               end)
            end))
         end
      end
   })
end

--- Read a file into lines
--- @param file string
--- @return table|nil
local function read_file_into_lines(file)
   local f = io.open(file, "r")
   if not f then
      return nil
   end
   local content = f:read("*a")
   f:close()
   return vim.split(content, '\n')
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
   config = util.load_from_json(config_file) or { include = {}, exclude = {} }
   return config
end

--- Truncate the file path by removing the root
--- @param filepath string
--- @return string
M.truncate_file_path = function(filepath)
   return filepath:sub(#M.root + 2)
end

--- Merge tags into the index
--- @param file_or_buf string|number # File or buffer number
--- @param tags table # Table of tags to merge
--- @param stat table|nil # Optional stat information for the file
M.merge_tags = function(file_or_buf, tags, stat)
   local bufnr = nil
   for tag,entry_array in pairs(tags) do
      M.data[tag] = M.data[tag] or {}
      -- Remove stale, old entries
      M.data[tag] = vim.tbl_filter(function(entry)
         local ret = (type(file_or_buf)=="string" and entry.file ~= file_or_buf)
            or (type(file_or_buf)=="number" and entry.bufnr ~= file_or_buf)
         return ret
      end, M.data[tag])

      -- Extract bufnr from the first entry
      if #entry_array > 0 and not bufnr then
         bufnr = entry_array[1].bufnr
      end

      for _, entry in ipairs(entry_array) do
         table.insert(M.data[tag], entry)
      end
   end

   if type(file_or_buf) == "number" then
      return
   end
   M.data_by_file[file_or_buf] =
      { hashtags = {}, next_extmark_id = 0,
         lastModifiedTime = stat and stat.mtime.nsec,
         bufnr = bufnr
      }
   for tag,entry_array in pairs(tags) do
      for _, entry in ipairs(entry_array) do
         table.insert(M.data_by_file[file_or_buf].hashtags, {
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

--- Index a file's hashtags
--- @param filename string
M.index_file = function(filename)
   local lines = read_file_into_lines(filename)
   if not lines then
      return nil
   end
   local tags = index_buffer({ file = filename, bufnr = nil }, lines)
   return tags
end

--- Index files in a directory
--- @param path string
--- @param extensions table
--- @return table The indexed data
function M.index_files(path_pattern, exclusions)
   return async.run(function()
      M.data = M.data or {}
      M.data_by_file = M.data_by_file or {}

      -- local files = vim.fs.find(function(name, path)
      --    -- #TODO make items ignorable
      --    if path:find('node_modules') or path:find('public') then
      --       return false
      --    end
      --    return vim.tbl_contains(extensions, name:match('.+%.(%w+)$'))
      -- end, { limit = math.huge, type = 'file', path = path})
      --
      -- for _, filename in ipairs(files) do
      --
      util.find_files_with_wildcard(M.root, path_pattern, exclusions, function(filename)
         local truncated_filename = M.truncate_file_path(filename)
         local stat = vim.loop.fs_stat(filename)

         if not stat then
            goto continue
         end
         local file_entry = M.data_by_file[truncated_filename]
         if file_entry and file_entry.lastModifiedTime == stat.mtime.nsec then
            goto continue
         elseif file_entry then
            print("File has been modified, reindexing: " .. filename)
         end

         --- Get information from this single file...
         local tags = M.index_file(truncated_filename)

         --- ...and merge it into the big data structure
         if tags then
            M.merge_tags(truncated_filename, tags, stat)
         end
          ::continue::
      end)
      -- end

      return M.data, M.data_by_file
   end,
   function(data, data_by_file)
      util.save_to_json(M.get_index_file(), data, data_by_file)
   end
   )
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
   M.index_files(config.include, config.exclude)
   init_autocommands()
end

return M
