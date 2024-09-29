local async = require('plenary.async')
-- local await = async.await
-- local Job = require('plenary.job')

local M = {
   context_lines = 1,
   root = nil
}

M.init = function()
   M.root = M.find_root_dir(vim.fn.getcwd())
   if not M.root then
      return
   end
   M.data = M.load_from_json(M.get_index_file())
   if not M.data then
      M.index_files(M.root, M.load_project_config().extensions)
   end
end

--- Saves data to json file
---
--- @param filename string (path to file)
--- @param args table (data to be stored in the json)
--- @return boolean
local function save_to_json(filename, args)
   local f = io.open(filename, "w")
   if not f then
      return false
   end
   local json = vim.json.encode(args)
   f:write(json)
   f:close()
   return true
end

M.load_from_json = function(filename)
   local f = io.open(filename, "r")
   if not f then
      return nil
   end
   local data = {}
   local content = f:read("*a")
   f:close()
   _, data = pcall(vim.json.decode, content, { object = true, array = true })
   assert(data, "Could not decode json")
   return data
end

--- Get the path to the file containing the index of hashtags
--- @return string
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
   config = M.load_from_json(config_file) or { extensions = {} }
   return config
end

--- Index files in a directory
--- @param path string
--- @param extensions table
--- @return table
function M.index_files(path, extensions)
   print("Extensions " .. vim.inspect(extensions))
   return async.run(function()
      M.data = {}

      local files = vim.fs.find(function(name)
         return vim.tbl_contains(extensions, name:match('.+%.(%w+)$'))
      end, { limit = math.huge, type = 'file', path = path})
      

      for _, filename in ipairs(files) do
         local f = io.open(filename, "r")
         if not f then
            goto continue
         end
         local content = f:read("*a")
         f:close()
         local lines = vim.split(content, '\n')
         for row, line in ipairs(lines) do
            local s, e = line:find('#[%u_]+')
            if s then
               local hashtag = line:sub(s, e)
               M.data[hashtag] = M.data[hashtag] or {}
               local ctx_lines = {}
               for i = row-M.context_lines, row+M.context_lines do
                  if i < 1 or i > #lines then
                     table.insert(ctx_lines, '')
                  end
                  table.insert(ctx_lines, lines[i])
               end
               filename = filename:sub(#path + 2) -- remove the root path including the slash
               table.insert(M.data[hashtag], {file = filename, lines = ctx_lines, from = s, to = e, row = row})
            end
         end
          ::continue::
      end

      save_to_json(M.get_index_file(), M.data)
   end,
   function(data)
   end
   )
end

function M.load_index_file()
   M.data = M.load_from_json(M.get_index_file())
end

return M
