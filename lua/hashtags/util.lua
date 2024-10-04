local M = {}

local DEBUG = true

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
local function parse_extensions_from_pattern(part)
  local extensions = {}
  local ext_match = part:match("{([^}]+)}")
  if ext_match then
    for ext in ext_match:gmatch("[^,]+") do
      table.insert(extensions, "." .. ext)
    end
  end
  return extensions
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

-- Helper function to check if a file or directory should be excluded
local function is_excluded(entry, exclude_patterns)
  for _, pattern in ipairs(exclude_patterns) do
    if entry:match(pattern) then
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
local function replace_glob_wildcards(path)
   return path:gsub("%.", "%%."):gsub("%*", ".*"):gsub("%?", "."):gsub("%+", ".+"):gsub("%-", "%%-")
end

-- Recursive file traversal using vim.loop with support for wildcards, extension matching, and exclusions
local function traverse_dir(dir, pattern_parts, index, exclude_patterns, callback)
  -- If index exceeds pattern parts, use the last part (since we're past '**')
  local current_parts = {}
  for _, part in ipairs(pattern_parts) do
    table.insert(current_parts, part[math.min(index, #part)])
  end

  -- local current_parts_exclude = {}
  -- for _, part in ipairs(exclude_patterns) do
  --   table.insert(current_parts_exclude, part[math.min(index, #part)])
  -- end

  -- local current_part = pattern_parts[math.min(index, #pattern_parts)]
  -- local current_part_exclude = exclude_patterns[math.min(index, #pattern_parts)]

  -- Parse extensions from the current part (if it contains an extension pattern)
  -- local extensions = parse_extensions_from_pattern(pattern_parts[#pattern_parts])

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
    -- if is_excluded(entry, exclude_patterns) then
    --   goto continue
    -- end

    -- If the current part is "**", match files or continue in all subdirectories at any depth
    local is_wildcard, wildcard_idx = M.array_any(current_parts, function(_, part) return part == "**" end)
      if is_wildcard then
         if stat and stat.type == "directory" then
           -- Recursively traverse subdirectories for "**"
           traverse_dir(path, pattern_parts, index, exclude_patterns, callback)
           -- Also attempt to match the next pattern part after "**"
           traverse_dir(path, pattern_parts, index + 1, exclude_patterns, callback)
         elseif stat and stat.type == "file" then
           local extensions = parse_extensions_from_pattern(pattern_parts[wildcard_idx][#pattern_parts[wildcard_idx]])
           -- Match against the final pattern part or extensions
           if has_extension(entry, extensions) then
             if DEBUG then 
                callback(path)
             end
             -- table.insert(result, path)
           end
         end
       elseif stat and stat.type == "directory" and vim.tbl_contains(current_parts, entry) then
         -- If it matches a directory name, continue traversal to the next part
         traverse_dir(path, pattern_parts, index + 1, exclude_patterns, callback)
       elseif stat and stat.type == "file" then
         local has_relevant_part, i = M.array_any(pattern_parts, function(_, parts) return index >= #parts end)
         if has_relevant_part then
         -- If it's a file and the last part, check for extensions and match
           local extensions = parse_extensions_from_pattern(pattern_parts[i][#pattern_parts[i]])
           if has_extension(entry, extensions) then
             if DEBUG then
                print("Adding:", path)
             end
             callback(path)
             -- table.insert(result, path)
           end
         end

         -- -- If it's a file and the last part, check for extensions and match
         -- local extensions = parse_extensions_from_pattern(pattern_parts[pattern_idx][#pattern_parts])
         -- if has_extension(entry, extensions) then
         --   callback(path)
         --   --table.insert(result, path)
         -- end
       elseif stat and stat.type == "file" and vim.tbl_contains(current_parts, "*") then
         -- If current part is "*" and we're at the last index, include the file
         if DEBUG then
            print("Adding:", path)
         end
         callback(path)
         -- table.insert(result, path)
       end
       ::continue::
    end
end

-- Wildcard search function with extensions and exclusions
-- @param path_patterns string[]: The path patterns to search for
-- @param exclude_patterns table: A list of patterns to exclude
-- @param callback function: A callback function to call for each file that matches the pattern
-- @return table: A list of files that match the pattern
M.find_files_with_wildcard = function(root, path_patterns, exclude_patterns, callback)
   local pattern_parts = {}
   for i, pattern in ipairs(path_patterns) do
      pattern_parts[i] = {}
      for _, part in ipairs(split_string(pattern, "/")) do
         table.insert(pattern_parts[i], part)
      end
   end
   -- local exclude_pattern_parts = {}
   for i,pattern in ipairs(exclude_patterns) do
      if pattern:sub(1, 2) == "./" then
         pattern = pattern:sub(3)
      end
      exclude_patterns[i] = replace_glob_wildcards(pattern)
   end
   -- for i, pattern in ipairs(exclude_patterns) do
   --    exclude_pattern_parts[i] = {}
   --    for _, part in ipairs(split_string(pattern, "/")) do
   --       table.insert(exclude_pattern_parts[i], part)
   --    end
   -- end
   if DEBUG then
      print("exclude_patterns", vim.inspect(exclude_patterns))
      print("pattern_parts", vim.inspect(pattern_parts))
   end
   return traverse_dir(root, pattern_parts, 2, exclude_patterns, callback)
end

return M
