local async = require('plenary.async')
local util = require('hashtags.util')
-- local await = async.await
-- local Job = require('plenary.job')

local DEBUG = false

local globals = require('hashtags.globals')

--- @class DataEntry
--- @field file string File that contains the hashtag
--- @field bufnr number|nil Buffer number of the file
--- @field lastModifiedTime number
--- @field mark_id number
--- @field lines table Context around the line containing the hashtag
--- @field from number Start column of the hashtag
--- @field to number End column of the hashtag
--- @field row number Line number of the hashtag
--- @field size number Size of the file

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
--- @field size number|nil
--- @field bufnr number|nil

--- @class EventArgs
--- @field buf number
--- @field event string
--- @field file string
--- @field group string
--- @field id number
--- @field match string

--- @class WorkspaceConfig
--- @field include string[]
--- @field exclude string[]

--- @class Internal
--- @field options Options|nil
--- @field root string|nil
--- @field data table<string, DataEntry[]>|nil
--- @field data_by_file table<string, DataByFileEntry>|nil
--- @field workspace_config WorkspaceConfig|nil
local M = {
   options = nil,
   root = nil,

   data = nil,
   data_by_file = nil,

   workspace_config = nil,
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
      on_create_func(hashtag, mark_id)
   end
end

--- Index a buffer's hashtags
--- @param file_or_buf table
--- @param lines table
--- @return table
local function index_buffer(file_or_buf, lines)
   local tags = {}
   local stat = file_or_buf.file and vim.loop.fs_stat(file_or_buf.file)
   local size
   if stat then
      size = stat.size
   end
   for row, line in ipairs(lines) do
      local hashtags = parse_line(line)
      for _,entry in ipairs(hashtags) do
         local hashtag = entry.hashtag
         local ctx_lines = {}
         tags[hashtag] = tags[hashtag] or {}
         for i = row-M.options.context_top, row+M.options.context_bottom do
            if i < 1 or i > #lines then
               table.insert(ctx_lines, '')
            end
            table.insert(ctx_lines, lines[i]:sub(1, math.min(100, #lines[i])))
         end
         table.insert(tags[hashtag],
            {file = file_or_buf.file,
               bufnr = file_or_buf.bufnr,
               lines = ctx_lines, from = entry.from, to = entry.from + #hashtag,
               row = row, mark_id = nil, lastModifiedTime = stat and stat.mtime.nsec,
               size = size
            })
      end
   end
   return tags
end

--- Reparse a buffer 
--- @param bufnr number
--- @param file string
local function reparse_buffer(bufnr, file)
   if file:find(M.root, 1, true) then
      file = M.truncate_file_path(file)
   end
   local file_entry = M.data_by_file[file]

   vim.api.nvim_buf_clear_namespace(bufnr, globals.HASHTAGS_HIGHLIGHT_NS, 0, -1)

   local tags = index_buffer({ file = file, bufnr = bufnr }, vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
   local stat = vim.loop.fs_stat(file)
   M.merge_tags(file, tags, stat)

   create_extmarks(bufnr, M.data_by_file[file].hashtags, function(hashtag, mark_id)
      hashtag.mark_id = mark_id
      file_entry.next_extmark_id = file_entry.next_extmark_id + 1
   end)
end

--- Initialize the autocommands:
--- 1) BufReadPost: When a new file is opened, create extmarks for the hashtags
--- 2) BufDelete: When a file is closed, remove the corresponding data
--- 3) TextChanged, TextChangedI: When a file is being edited, check for new hashtags
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
   vim.api.nvim_create_autocmd({'BufDelete'}, {
      group = globals.HASHTAGS_AUGROUP,
      --- @type fun(ev: EventArgs)
      callback = function(ev)
         local file_entry = M.data_by_file[ev.file]
         if not file_entry then
            return
         end

         file_entry.bufnr = nil
         file_entry.next_extmark_id = 0
         for _,entry in ipairs(file_entry.hashtags) do
            entry.mark_id = nil
            for _,entry2 in ipairs(M.data[entry.hashtag]) do
               if entry2.file == ev.file and entry2.row == entry.row and entry2.from == entry.from then
                  entry2.bufnr = nil
                  entry2.mark_id = nil
                  if DEBUG then
                     print("Erased entry for hashtag ", entry.hashtag, " in buffer ", ev.buf)
                  end
               end
            end
         end
         if DEBUG then
            print("Erased buffer ", ev.buf, " from file ", ev.file)
         end
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

         assert(file_entry.size)
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
         elseif not M.options.refresh_file_size_limit or file_entry.size <= M.options.refresh_file_size_limit then
            buf_timer:start(M.options.refresh_timeout, 0, vim.schedule_wrap(function()
               reparse_buffer(ev.buf, ev.file)
            end))
         end
      end
   })
end

--- Initialize the commands
--- 1) Reparse: Reparse the current buffer
--- 2) RegenIndex: Regenerate the index
local function init_commands()
   vim.api.nvim_create_user_command(globals.COMMAND_PREFIX .. "Reparse", function(_)
      local bufnr = vim.api.nvim_get_current_buf()
      local file = vim.api.nvim_buf_get_name(bufnr)
      reparse_buffer(bufnr, file)
   end, {})
   vim.api.nvim_create_user_command(globals.COMMAND_PREFIX .. "RegenIndex", function(_)
      M.data = nil
      M.data_by_file = nil
      M.index_files(M.workspace_config.include, M.workspace_config.exclude)
      vim.notify("Index regenerated", vim.log.levels.INFO)
   end, {})
   vim.api.nvim_create_user_command(globals.COMMAND_PREFIX .. "GenConfig", function(_)
      local config_file = vim.fs.joinpath(M.root, globals.CONFIG_FILE_NAME)
      if vim.loop.fs_stat(config_file) then
         vim.notify("Config file " .. globals.CONFIG_FILE_NAME .. " already exists. Please delete it first to generate a new one.", vim.log.levels.WARN)
         return
      end
      local new_config = {
         include = {
            "./**/*.{js,html}",
         },
         exclude = {
            "./node_modules",
            "./.git",
            "./public",
         }
      }
      if util.save_to_json(config_file, new_config) then
         M.workspace_config = new_config
         vim.notify("Config file " .. globals.CONFIG_FILE_NAME .. " generated.", vim.log.levels.INFO)
      end
   end, {})
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
   local config_file = vim.fs.joinpath(M.root, globals.CONFIG_FILE_NAME)
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
         bufnr = bufnr,
         size = stat and stat.size
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
--- @param path_patterns string[]
--- @param exclusions table
function M.index_files(path_patterns, exclusions)
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
      util.find_files_with_wildcard(M.root, path_patterns, exclusions, function(filename)
         local truncated_filename = M.truncate_file_path(filename)
         local stat = vim.loop.fs_stat(filename)

         if not stat then
            goto continue
         end
         local file_entry = M.data_by_file[truncated_filename]
         if file_entry and file_entry.lastModifiedTime == stat.mtime.nsec then
            goto continue
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

--- Go to the next hashtag
--- @param hashtag string
--- @param direction number +1 or -1 for forward or backward
M.nav = function(hashtag, direction)
   assert(type(direction) == 'number')
   assert(direction == 1 or direction == -1)

   if not M.data[hashtag] then
      return
   end

   local tag_entry = M.data[hashtag]

   local current = vim.api.nvim_get_current_buf()
   local this_file = M.truncate_file_path(vim.api.nvim_buf_get_name(current))
   local cursor_pos = vim.api.nvim_win_get_cursor(0)
   local next_idx = 0

   for idx, entry in ipairs(tag_entry) do
      if entry.file == this_file and entry.row == cursor_pos[1] and cursor_pos[2] >= entry.from and cursor_pos[2] <= entry.to then
         next_idx = (idx-1 + direction) % #tag_entry
         next_idx = next_idx + 1
         break
      end
   end
   if next_idx == 0 then
      return
   end
   --- @type DataEntry
   local next = tag_entry[next_idx]
   assert(next and (next.file or next.bufnr))
   if next then
      if next.bufnr then
         vim.api.nvim_set_current_buf(next.bufnr)
      else
         vim.api.nvim_command('e ' .. next.file)
      end
      vim.api.nvim_win_set_cursor(0, {next.row, next.from})
   end
end

--- Initialize the internals
---
--- This function will try to find the root directory of the project and load the index file
--- @param opts Options
M.init = function(opts)
   assert(opts.refresh_file_size_limit)
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
   M.workspace_config = M.load_project_config()
   M.index_files(M.workspace_config.include, M.workspace_config.exclude)
   init_autocommands()
   init_commands()
end

return M
