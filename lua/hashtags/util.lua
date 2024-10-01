local M = {}

--- Saves data to json file
---
--- @param filename string (path to file)
--- @param args table (data to be stored in the json)
--- @return boolean
M.save_to_json = function(filename, ...)
   local f = io.open(filename, "w")
   if not f then
      return false
   end
   local write_data = {}
   for _, arg in ipairs({...}) do
      table.insert(write_data, arg)
   end
   local json = vim.json.encode(write_data)
   f:write(json)
   f:close()
   return true
end

--- Loads data from json file
---
--- @param filename string (path to file)
--- @return table|nil
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
   if #data == 1 then
      return data[1]
   end
   return data
end

return M
