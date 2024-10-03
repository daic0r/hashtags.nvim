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

-- Recursive file traversal using vim.loop with support for wildcards, extension matching, and exclusions
local function traverse_dir(dir, pattern_parts, index, exclude_patterns, callback)
  -- If index exceeds pattern parts, use the last part (since we're past '**')
  local current_part = pattern_parts[math.min(index, #pattern_parts)]

  -- Parse extensions from the current part (if it contains an extension pattern)
  local extensions = parse_extensions_from_pattern(pattern_parts[#pattern_parts])
    --current_part = current_part:gsub("{[^}]+}", "*")  -- Replace {lua,js,json} with '*' for traversal

  local handle = vim.loop.fs_scandir(dir)
  if not handle then
    print("Error scanning directory:", dir)
    return result
  end

  -- Iterate over all entries in the current directory
  while true do
    local entry = vim.loop.fs_scandir_next(handle)
    if not entry then break end
    local path = dir .. "/" .. entry
    local stat = vim.loop.fs_stat(path)

    -- Debugging: Print the current directory and file
    --print("Scanning:", path)

    -- Skip files or directories that match the exclude patterns
    if is_excluded(entry, exclude_patterns) then
      goto continue
    end

    -- If the current part is "**", match files or continue in all subdirectories at any depth
    if current_part == "**" then
      if stat and stat.type == "directory" then
        -- Recursively traverse subdirectories for "**"
        traverse_dir(path, pattern_parts, index, exclude_patterns)
        -- Also attempt to match the next pattern part after "**"
        traverse_dir(path, pattern_parts, index + 1, exclude_patterns)
      elseif stat and stat.type == "file" then
        -- Match against the final pattern part or extensions
        if has_extension(entry, extensions) then
          callback(path)
          -- table.insert(result, path)
        end
      end
    elseif stat and stat.type == "directory" and current_part == entry then
      -- If it matches a directory name, continue traversal to the next part
      traverse_dir(path, pattern_parts, index + 1, exclude_patterns)
    elseif stat and stat.type == "file" and index >= #pattern_parts then
      -- If it's a file and the last part, check for extensions and match
      if has_extension(entry, extensions) then
        callback(path)
        --table.insert(result, path)
      end
    elseif stat and stat.type == "file" and current_part == "*" then
      -- If current part is "*" and we're at the last index, include the file
      callback(path)
      -- table.insert(result, path)
    end
    ::continue::
  end
end

-- Wildcard search function with extensions and exclusions
-- @param path_pattern string: The path pattern to search for
-- @param exclude_patterns table: A list of patterns to exclude
-- @param callback function: A callback function to call for each file that matches the pattern
-- @return table: A list of files that match the pattern
M.find_files_with_wildcard = function(path_pattern, exclude_patterns, callback)
   local parts = split_string(path_pattern, "/")
   local base_dir = parts[1] ~= "" and parts[1] or "."
   return traverse_dir(base_dir, parts, 2, exclude_patterns, callback)
end

return M
