local M = {}

local DEBUG = false

M.array_any = function(tbl, fn)
   for i, v in ipairs(tbl) do
      if fn(i, v) then
         return true, i
      end
   end
   return false, nil
end

--- Saves data to json file
---
--- @param filename string (path to file)
--- @param ... table[]|table (data to be stored in the json)
--- @return boolean
M.save_to_json = function(filename, ...)
   local f = io.open(filename, "w")
   if not f then
      return false
   end
   local write_data = {}
   if #{...} == 1 and type(...) == "table" then
      write_data = ...
   else
      for _, arg in ipairs({...}) do
         table.insert(write_data, arg)
      end
   end
   local json = vim.json.encode(write_data)
   -- Attempt to format with jq
   local ok, promise = pcall(vim.system, { 'jq' }, { stdin = json, text = true })
   if ok then
      json = promise:wait().stdout
   end
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

--------------------------------------------------------------------------------
-- File traversal

-- Helper function to split string by a delimiter
local function split_string(str, delimiter)
   local result = {}
   for match in (str .. delimiter):gmatch("(.-)" .. delimiter) do
      table.insert(result, match)
   end
   return result
end

-- Helper function to parse extensions from the pattern
M.parse_extensions_from_pattern = function(part)
   local extensions = {}
   local ext_match = part:match("%.{([^}]+)}$")
   if ext_match then
      for ext in ext_match:gmatch("[^,]+") do
         table.insert(extensions, ext)
      end
      return extensions
   end
   ext_match = part:match("%.(.+)$")
   if ext_match then
      table.insert(extensions, ext_match)
      return extensions
   end
   ext_match = part:match("%.%*$")
   if ext_match then
      table.insert(extensions, "*")
      return extensions
   end
   return extensions
end

M.get_file_stem = function(file)
   local match_with_dot = file:match("^(.+)%.")
   if not match_with_dot then
      return file
   end
   return match_with_dot
end

--- Helper function to match a file to a pattern
--- @param file string: The file to match
--- @param pattern string: The pattern to match against
---
M.match_file_to_pattern = function(file, pattern)
   local stem = M.get_file_stem(pattern)
   assert(stem)
   stem = M.replace_glob_wildcards(stem)
   local extensions = M.parse_extensions_from_pattern(pattern)
   if #extensions == 0 then
      return file:match(stem) ~= nil
   end
   for _, ext in ipairs(extensions) do
      if file:match(stem .. "%." .. ext) then
         return true
      end
   end
   return false
end

-- Helper function to check if a file matches the allowed extensions
local function has_extension(file, extensions)
   if #extensions == 0 then return true end  -- If no specific extensions are required, allow all files
   if vim.tbl_contains(extensions, "*") then return true end  -- If '*' is in the extensions, allow all files
   for _, ext in ipairs(extensions) do
      if file:sub(-#ext) == ext then
         return true
      end
   end
   return false
end

--- Helper function to replace glob wildcards with Lua patterns
--- This is necessary because Lua patterns are not the same as glob patterns
--- and we need to convert them to match the same files
--- @param path string: The path to replace wildcards in
--- @return string: The path with wildcards replaced
M.replace_glob_wildcards = function(path)
   return (path:gsub("%%", "%%%%"):gsub("%.", "%%."):gsub("%*", ".*"):gsub("%?", "."):gsub("%+", ".+"):gsub("%-", "%%-"):gsub("%$", "%%$"))
end

--- Traverse directory recursively with support for glob patterns
--- @param dir string: The directory to traverse
--- @param pattern_parts string[][]: The pattern parts, each sub-array contains the parts of a pattern separated by '/'
--- @param index number: The current traversal depth
--- @param exclude_patterns string[]: A list of patterns to exclude; can start with ./ or not
--- @param inside_double_asterisk boolean: Whether we're inside a '**' pattern or beyond
--- @param callback function: A callback function to call for each file that matches the pattern
local function traverse_dir(dir, pattern_parts, index, exclude_patterns, inside_double_asterisk, callback)
   -- If index exceeds pattern parts, use the last part (since we're past '**')
   local current_parts = {}
   for _, part in ipairs(pattern_parts) do
      table.insert(current_parts, part[math.min(index, #part)])
   end

   local handle = vim.loop.fs_scandir(dir)
   if not handle then
      print("Error scanning directory:", dir)
      return
   end

   -- Iterate over all entries in the current directory
   while true do
      local entry = vim.loop.fs_scandir_next(handle)
      if not entry then break end
      local path = dir .. "/" .. entry
      local stat = vim.loop.fs_stat(path)

      -- Skip files or directories that match the exclude patterns
      for _, exclude in ipairs(exclude_patterns) do
         if exclude ~= ".*.*" and path:match(exclude .. "$") then
            if DEBUG then
               print("Exclude  ", path, " matched:", exclude)
            end
            goto continue
         end
      end

      -- If the current part is "**", match files or continue in all subdirectories at any depth
      local any_current_part_is_double_astk = M.array_any(current_parts, function(_, part) return part == "**" end)
      local is_wildcard = inside_double_asterisk or any_current_part_is_double_astk

      if stat and stat.type == "directory" then
         traverse_dir(path, pattern_parts, index + 1, exclude_patterns, is_wildcard, callback)
      elseif stat and stat.type == "file" then
         local reached_file_depth, i = M.array_any(pattern_parts, function(_, parts) return index >= #parts end)
         if reached_file_depth then
            -- Check if file matches pattern, including concrete directory names
            -- i.e. ./**/server/*.go should match ./home/user/project/server/main.go
            -- therefore we walk back from the back (*.go) until we reach ** or the beginning
            local matches = true
            local path_parts = split_string(path, "/")
            local j = 0
            local dir_pattern = nil
            local path_part = nil
            while (not dir_pattern or dir_pattern ~= "**") and j < math.min(#pattern_parts[i], #path_parts) do
               dir_pattern = pattern_parts[i][#pattern_parts[i]-j]
               path_part = path_parts[#path_parts-j]
               matches = matches and M.match_file_to_pattern(path_part, dir_pattern)
               j = j + 1
            end
            if matches then
               if DEBUG then
                  print("Adding:", path)
               end
               callback(path)
               -- table.insert(result, path)
            end
         end
      end
      ::continue::
   end
end

--- Wildcard search function with extensions and exclusions
--- @param root string: The root directory to start the search from
--- @param path_patterns string[]: The path patterns to search for
--- @param exclude_patterns table: A list of patterns to exclude
--- @param callback function: A callback function to call for each file that matches the pattern
M.find_files_with_wildcard = function(root, path_patterns, exclude_patterns, callback)
   local pattern_parts = {}
   -- Split the patterns into parts
   for i, pattern in ipairs(path_patterns) do
      pattern_parts[i] = {}
      for _, part in ipairs(split_string(pattern, "/")) do
         table.insert(pattern_parts[i], part)
      end
   end

   for i,pattern in ipairs(exclude_patterns) do
      if pattern:sub(1, 2) == "./" then
         pattern = pattern:sub(3)
      end
      exclude_patterns[i] = M.replace_glob_wildcards(pattern)
   end

   if DEBUG then
      print("exclude_patterns", vim.inspect(exclude_patterns))
      print("pattern_parts", vim.inspect(pattern_parts))
   end
   traverse_dir(root, pattern_parts, 2, exclude_patterns, false, callback)
end

return M
