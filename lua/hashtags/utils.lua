local async = require('plenary.async')
-- local await = async.await
-- local Job = require('plenary.job')

local M = {}
-- Saves data to json file
--
-- @param filename: string (path to file)
-- @param args: table (data to be stored in the json)
-- @return boolean
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

local function load_from_json(filename)
   local f = io.open(filename, "r")
   if not f then
      return {}
   end
   local data = {}
   if f then
      local content = f:read("*a")
      f:close()
      _, data = pcall(vim.json.decode, content, { object = true, array = true })
      assert(data, "Could not decode json")
   end
   return data
end

local get_index_file = function()
   return vim.fn.stdpath('cache') .. '/hashtags.json'
end

function M:index_files(path, extensions)
   return async.run(function()
      self.data = {}

      local k = vim.fs.find(function(name)
         return name:match('%.lua$')
      end, { limit = math.huge, type = 'file', path = path})

      for _, filename in ipairs(k) do
         local f = io.open(filename, "r")
         local content = f:read("*a")
         local lines = vim.split(content, '\n')
         for row, line in ipairs(lines) do
            local s, e = line:find('#[%u_]+')
            if s then
               local hashtag = line:sub(s, e)
               self.data[hashtag] = self.data[hashtag] or {}
               table.insert(self.data[hashtag], {file = filename, line = line, from = s, to = e, row = row})
            end
         end
      end

      save_to_json(get_index_file(), self.data)
   end,
   function(data)
      print(vim.inspect(self.data))
   end
   )
end


return M
