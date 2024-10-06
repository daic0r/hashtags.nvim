describe("Util function tests:", function()
   local util = require("hashtags.util")

   it("Get file stem", function()
      local file = "test.lua"
      local stem = util.get_file_stem(file)
      assert.are.same("test", stem)

      file = "test"
      stem = util.get_file_stem(file)
      assert.are.same("test", stem)

      file = "test.lua.md"
      stem = util.get_file_stem(file)
      assert.are.same("test.lua", stem)

      file = "*.lua"
      stem = util.get_file_stem(file)
      assert.are.same("*", stem)
   end)

   it("Parse extensions", function()
      local part = "test.{lua,md}"
      local extensions = util.parse_extensions_from_pattern(part)
      assert.are.same({"lua", "md"}, extensions)

      part = "test.lua"
      extensions = util.parse_extensions_from_pattern(part)
      assert.are.same({"lua"}, extensions)

      part = "test.*"
      extensions = util.parse_extensions_from_pattern(part)
      assert.are.same({"*"}, extensions)

      part = "*.lua"
      extensions = util.parse_extensions_from_pattern(part)
      assert.are.same({"lua"}, extensions)
   end)

   it("Replace wildcards", function()
      local pattern = "test.*"
      pattern = util.replace_glob_wildcards(pattern)
      assert.are.same("test%..*", pattern)
   end)

   it("Match file pattern", function()
      local pattern = "test.*"
      assert.is_true(util.match_file_to_pattern("test.lua", pattern))

      pattern = "*.lua"
      assert.is_true(util.match_file_to_pattern("test.lua", pattern))

      pattern = "te*.lua"
      assert.is_true(util.match_file_to_pattern("test.lua", pattern))

      pattern = "te*"
      assert.is_true(util.match_file_to_pattern("test.lua", pattern))
   end)
end)
