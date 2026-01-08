-- test_utils.lua
-- Unit tests for utils.lua
-- Run standalone with: lua test_utils.lua

-- Adjust package path to find Libs
package.path = package.path .. ";../Libs/?.lua"

local Utils = require("utils")

-- ============================================================================
-- TEST FRAMEWORK
-- ============================================================================

local passed = 0
local failed = 0

local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then
        print("[PASS] " .. name)
        passed = passed + 1
    else
        print("[FAIL] " .. name .. ": " .. tostring(err))
        failed = failed + 1
    end
end

local function assert_eq(actual, expected, msg)
    if actual ~= expected then
        error((msg or "Assertion failed") ..
              ": expected " .. tostring(expected) ..
              ", got " .. tostring(actual))
    end
end

local function assert_true(value, msg)
    if not value then
        error((msg or "Expected true") .. ", got " .. tostring(value))
    end
end

local function assert_false(value, msg)
    if value then
        error((msg or "Expected false") .. ", got " .. tostring(value))
    end
end

local function assert_nil(value, msg)
    if value ~= nil then
        error((msg or "Expected nil") .. ", got " .. tostring(value))
    end
end

local function assert_not_nil(value, msg)
    if value == nil then
        error(msg or "Expected non-nil value")
    end
end

local function table_eq(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then
        return a == b
    end
    for k, v in pairs(a) do
        if not table_eq(v, b[k]) then return false end
    end
    for k, v in pairs(b) do
        if not table_eq(v, a[k]) then return false end
    end
    return true
end

local function assert_table_eq(actual, expected, msg)
    if not table_eq(actual, expected) then
        local function serialize(t)
            if type(t) ~= "table" then return tostring(t) end
            local parts = {}
            for k, v in pairs(t) do
                table.insert(parts, tostring(k) .. "=" .. serialize(v))
            end
            return "{" .. table.concat(parts, ", ") .. "}"
        end
        error((msg or "Tables not equal") ..
              ": expected " .. serialize(expected) ..
              ", got " .. serialize(actual))
    end
end

-- ============================================================================
-- PATH UTILITIES TESTS
-- ============================================================================

print("\n=== PATH UTILITIES TESTS ===")

test("SEP is defined", function()
    assert_not_nil(Utils.SEP)
    assert_true(Utils.SEP == "/" or Utils.SEP == "\\", "SEP should be / or \\")
end)

-- normalize_path tests
test("normalize_path with forward slashes", function()
    local result = Utils.normalize_path("a/b/c")
    -- Should convert to OS separator
    if Utils.SEP == "/" then
        assert_eq(result, "a/b/c")
    else
        assert_eq(result, "a\\b\\c")
    end
end)

test("normalize_path with backslashes", function()
    local result = Utils.normalize_path("a\\b\\c")
    if Utils.SEP == "/" then
        assert_eq(result, "a/b/c")
    else
        assert_eq(result, "a\\b\\c")
    end
end)

test("normalize_path with mixed slashes", function()
    local result = Utils.normalize_path("a/b\\c/d")
    if Utils.SEP == "/" then
        assert_eq(result, "a/b/c/d")
    else
        assert_eq(result, "a\\b\\c\\d")
    end
end)

test("normalize_path removes duplicate separators", function()
    local result = Utils.normalize_path("a//b///c")
    if Utils.SEP == "/" then
        assert_eq(result, "a/b/c")
    else
        assert_eq(result, "a\\b\\c")
    end
end)

test("normalize_path with nil returns nil", function()
    assert_nil(Utils.normalize_path(nil))
end)

test("normalize_path with empty string", function()
    assert_eq(Utils.normalize_path(""), "")
end)

-- join_path tests
test("join_path basic", function()
    local result = Utils.join_path("a", "b", "c")
    if Utils.SEP == "/" then
        assert_eq(result, "a/b/c")
    else
        assert_eq(result, "a\\b\\c")
    end
end)

test("join_path with trailing separator", function()
    local result = Utils.join_path("a/", "b", "c")
    if Utils.SEP == "/" then
        assert_eq(result, "a/b/c")
    else
        assert_eq(result, "a\\b\\c")
    end
end)

test("join_path with leading separator on segment", function()
    local result = Utils.join_path("a", "/b", "c")
    if Utils.SEP == "/" then
        assert_eq(result, "a/b/c")
    else
        assert_eq(result, "a\\b\\c")
    end
end)

test("join_path with empty segments", function()
    local result = Utils.join_path("a", "", "c")
    if Utils.SEP == "/" then
        assert_eq(result, "a/c")
    else
        assert_eq(result, "a\\c")
    end
end)

test("join_path with nil segments skips nil", function()
    -- Note: The implementation skips nil segments
    -- Due to how ipairs works, nil in the middle may truncate varargs
    local result = Utils.join_path("a", nil, "c")
    -- ipairs stops at nil, so only "a" is processed
    -- This is expected Lua behavior with varargs
    assert_eq(result, "a")
end)

test("join_path single segment", function()
    local result = Utils.join_path("a")
    assert_eq(result, "a")
end)

test("join_path no segments", function()
    local result = Utils.join_path()
    assert_eq(result, "")
end)

-- get_directory tests
test("get_directory basic", function()
    local result = Utils.get_directory("/path/to/file.txt")
    if Utils.SEP == "/" then
        assert_eq(result, "/path/to")
    else
        assert_eq(result, "\\path\\to")
    end
end)

test("get_directory file only returns .", function()
    local result = Utils.get_directory("file.txt")
    assert_eq(result, ".")
end)

test("get_directory root path", function()
    local result = Utils.get_directory("/file.txt")
    assert_eq(result, Utils.SEP)
end)

test("get_directory with nil", function()
    assert_nil(Utils.get_directory(nil))
end)

-- get_filename tests
test("get_filename basic", function()
    local result = Utils.get_filename("/path/to/file.txt")
    assert_eq(result, "file.txt")
end)

test("get_filename file only", function()
    local result = Utils.get_filename("file.txt")
    assert_eq(result, "file.txt")
end)

test("get_filename with backslash path", function()
    local result = Utils.get_filename("C:\\path\\to\\file.txt")
    assert_eq(result, "file.txt")
end)

test("get_filename with nil", function()
    assert_nil(Utils.get_filename(nil))
end)

-- ============================================================================
-- STRING UTILITIES TESTS
-- ============================================================================

print("\n=== STRING UTILITIES TESTS ===")

-- trim tests
test("trim leading and trailing spaces", function()
    assert_eq(Utils.trim("  hello  "), "hello")
end)

test("trim only leading spaces", function()
    assert_eq(Utils.trim("  hello"), "hello")
end)

test("trim only trailing spaces", function()
    assert_eq(Utils.trim("hello  "), "hello")
end)

test("trim with tabs", function()
    assert_eq(Utils.trim("\t\thello\t"), "hello")
end)

test("trim with newlines", function()
    assert_eq(Utils.trim("\n\nhello\n"), "hello")
end)

test("trim empty string", function()
    assert_eq(Utils.trim(""), "")
end)

test("trim whitespace only", function()
    assert_eq(Utils.trim("   "), "")
end)

test("trim with nil", function()
    assert_nil(Utils.trim(nil))
end)

test("trim preserves internal spaces", function()
    assert_eq(Utils.trim("  hello world  "), "hello world")
end)

-- split tests
test("split with comma", function()
    local result = Utils.split("a,b,c", ",")
    assert_table_eq(result, {"a", "b", "c"})
end)

test("split with space", function()
    local result = Utils.split("a b c", " ")
    assert_table_eq(result, {"a", "b", "c"})
end)

test("split default separator (comma)", function()
    local result = Utils.split("a,b,c")
    assert_table_eq(result, {"a", "b", "c"})
end)

test("split with no separator found", function()
    local result = Utils.split("abc", ",")
    assert_table_eq(result, {"abc"})
end)

test("split empty string", function()
    local result = Utils.split("", ",")
    assert_table_eq(result, {""})
end)

test("split with nil", function()
    local result = Utils.split(nil, ",")
    assert_table_eq(result, {})
end)

test("split with empty separator (chars)", function()
    local result = Utils.split("abc", "")
    assert_table_eq(result, {"a", "b", "c"})
end)

test("split with trailing separator", function()
    local result = Utils.split("a,b,c,", ",")
    assert_table_eq(result, {"a", "b", "c", ""})
end)

test("split with leading separator", function()
    local result = Utils.split(",a,b", ",")
    assert_table_eq(result, {"", "a", "b"})
end)

test("split with multi-char separator", function()
    local result = Utils.split("a::b::c", "::")
    assert_table_eq(result, {"a", "b", "c"})
end)

test("split with special regex chars", function()
    local result = Utils.split("a.b.c", ".")
    assert_table_eq(result, {"a", "b", "c"})
end)

-- ============================================================================
-- FILE UTILITIES TESTS
-- ============================================================================

print("\n=== FILE UTILITIES TESTS ===")

-- Create temp file for testing
local test_dir = os.getenv("TMPDIR") or "/tmp"
local test_file = test_dir .. "/reamd_test_utils_" .. os.time() .. ".txt"
local test_content = "Hello, World!\nLine 2\n"

test("write_file creates file", function()
    local success, err = Utils.write_file(test_file, test_content)
    assert_true(success, err)
end)

test("file_exists returns true for existing file", function()
    assert_true(Utils.file_exists(test_file))
end)

test("file_exists returns false for non-existent file", function()
    assert_false(Utils.file_exists("/nonexistent/file/path.txt"))
end)

test("file_exists with nil", function()
    assert_false(Utils.file_exists(nil))
end)

test("read_file returns content", function()
    local content, err = Utils.read_file(test_file)
    assert_not_nil(content, err)
    assert_eq(content, test_content)
end)

test("read_file with non-existent file returns nil and error", function()
    local content, err = Utils.read_file("/nonexistent/file/path.txt")
    assert_nil(content)
    assert_not_nil(err)
end)

test("read_file with nil", function()
    local content, err = Utils.read_file(nil)
    assert_nil(content)
    assert_eq(err, "No path provided")
end)

test("write_file with nil path", function()
    local success, err = Utils.write_file(nil, "content")
    assert_false(success)
    assert_eq(err, "No path provided")
end)

test("write_file with nil content", function()
    local success, err = Utils.write_file(test_file, nil)
    assert_false(success)
    assert_eq(err, "No content provided")
end)

test("write_file overwrites existing file", function()
    local new_content = "New content"
    local success = Utils.write_file(test_file, new_content)
    assert_true(success)
    local content = Utils.read_file(test_file)
    assert_eq(content, new_content)
end)

-- Cleanup test file
os.remove(test_file)

-- ============================================================================
-- ERROR HANDLING TESTS
-- ============================================================================

print("\n=== ERROR HANDLING TESTS ===")

-- safe_call tests
test("safe_call with successful function", function()
    local result, err = Utils.safe_call(function() return 42 end)
    assert_eq(result, 42)
    assert_nil(err)
end)

test("safe_call with function returning multiple values", function()
    local result = Utils.safe_call(function() return 1, 2, 3 end)
    -- Only first return value is captured
    assert_eq(result, 1)
end)

test("safe_call with function returning nil", function()
    local result, err = Utils.safe_call(function() return nil end)
    -- nil result, no error
    assert_nil(result)
    assert_nil(err)
end)

test("safe_call with erroring function", function()
    local result, err = Utils.safe_call(function() error("test error") end)
    assert_nil(result)
    assert_not_nil(err)
    assert_true(err:find("test error") ~= nil, "Error should contain message")
end)

test("safe_call with nil function", function()
    local result, err = Utils.safe_call(nil)
    assert_nil(result)
    assert_eq(err, "Not a function")
end)

test("safe_call with non-function", function()
    local result, err = Utils.safe_call("not a function")
    assert_nil(result)
    assert_eq(err, "Not a function")
end)

test("safe_call with arguments", function()
    local result = Utils.safe_call(function(a, b) return a + b end, 10, 20)
    assert_eq(result, 30)
end)

test("safe_call with function that accesses upvalue", function()
    local x = 100
    local result = Utils.safe_call(function() return x * 2 end)
    assert_eq(result, 200)
end)

-- ============================================================================
-- EDGE CASES
-- ============================================================================

print("\n=== EDGE CASES ===")

test("normalize_path with single char", function()
    assert_eq(Utils.normalize_path("a"), "a")
end)

test("join_path with absolute path in middle", function()
    -- This is a common edge case - absolute path in middle should be handled
    local result = Utils.join_path("a", "/b", "c")
    -- Leading slash on non-first segment is removed
    if Utils.SEP == "/" then
        assert_eq(result, "a/b/c")
    else
        assert_eq(result, "a\\b\\c")
    end
end)

test("get_directory with only separator", function()
    local result = Utils.get_directory("/")
    assert_eq(result, Utils.SEP)
end)

test("split with consecutive separators", function()
    local result = Utils.split("a,,b", ",")
    assert_table_eq(result, {"a", "", "b"})
end)

test("trim with mixed whitespace", function()
    assert_eq(Utils.trim(" \t\n hello \t\n "), "hello")
end)

-- ============================================================================
-- RESULTS
-- ============================================================================

print("\n" .. string.rep("=", 50))
print("UTILS TEST RESULTS: " .. passed .. " passed, " .. failed .. " failed")
print(string.rep("=", 50))

if failed > 0 then
    os.exit(1)
else
    os.exit(0)
end
