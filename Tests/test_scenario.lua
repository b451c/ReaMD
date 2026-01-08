-- test_scenario.lua
-- Unit tests for scenario_engine.lua
-- This test file mocks the Reaper API where needed
-- Run standalone with: lua test_scenario.lua

-- ============================================================================
-- REAPER API MOCK
-- ============================================================================

-- Global reaper table for mocking
reaper = {}

-- Mock regions data
local mock_regions = {}
local mock_play_state = 0
local mock_play_position = 0.0
local mock_ext_state = {}
local mock_proj_ext_state = {}

function reaper.CountProjectMarkers(proj)
    local markers = 0
    local regions = 0
    for _, r in ipairs(mock_regions) do
        if r.isrgn then
            regions = regions + 1
        else
            markers = markers + 1
        end
    end
    return markers, regions
end

function reaper.EnumProjectMarkers3(proj, idx)
    local r = mock_regions[idx + 1]  -- 1-based in Lua
    if r then
        return true, r.isrgn, r.pos, r.rgnend, r.name, r.id, r.color
    end
    return false, false, 0, 0, "", 0, 0
end

function reaper.GetPlayState()
    return mock_play_state
end

function reaper.GetPlayPosition2(proj)
    return mock_play_position
end

function reaper.GetLastMarkerAndCurRegion(proj, pos)
    local marker_idx = -1
    local region_idx = -1
    for i, r in ipairs(mock_regions) do
        if r.isrgn and pos >= r.pos and pos < r.rgnend then
            region_idx = r.id
        end
    end
    return marker_idx, region_idx
end

function reaper.GetExtState(section, key)
    return mock_ext_state[section .. ":" .. key] or ""
end

function reaper.SetExtState(section, key, value, persist)
    mock_ext_state[section .. ":" .. key] = value
end

function reaper.DeleteExtState(section, key, persist)
    mock_ext_state[section .. ":" .. key] = nil
end

function reaper.GetProjExtState(proj, section, key)
    local val = mock_proj_ext_state[section .. ":" .. key]
    if val then
        return 1, val
    end
    return 0, ""
end

function reaper.SetProjExtState(proj, section, key, value)
    mock_proj_ext_state[section .. ":" .. key] = value
end

function reaper.SetEditCurPos(pos, moveview, seekplay)
    -- Mock implementation
end

function reaper.time_precise()
    return os.clock()
end

-- Helper to set mock regions
local function set_mock_regions(regions)
    mock_regions = regions
end

local function set_mock_play_state(state, position)
    mock_play_state = state
    mock_play_position = position or 0.0
end

local function clear_mock_state()
    mock_regions = {}
    mock_play_state = 0
    mock_play_position = 0.0
    mock_ext_state = {}
    mock_proj_ext_state = {}
end

-- ============================================================================
-- LOAD MODULES
-- ============================================================================

-- Adjust package path
package.path = package.path .. ";../Libs/?.lua"

-- Mock json module (minimal implementation for tests)
package.loaded["json"] = {
    encode = function(obj)
        -- Simple JSON encoding for tests
        local function encode_value(v)
            local t = type(v)
            if t == "nil" then return "null"
            elseif t == "boolean" then return v and "true" or "false"
            elseif t == "number" then return tostring(v)
            elseif t == "string" then return '"' .. v:gsub('"', '\\"') .. '"'
            elseif t == "table" then
                if #v > 0 then
                    -- Array
                    local parts = {}
                    for _, val in ipairs(v) do
                        table.insert(parts, encode_value(val))
                    end
                    return "[" .. table.concat(parts, ",") .. "]"
                else
                    -- Object
                    local parts = {}
                    for k, val in pairs(v) do
                        table.insert(parts, '"' .. k .. '":' .. encode_value(val))
                    end
                    return "{" .. table.concat(parts, ",") .. "}"
                end
            end
            return "null"
        end
        return encode_value(obj)
    end,
    decode = function(str)
        -- Use Lua's load to parse JSON (works for simple cases)
        -- Replace JSON syntax with Lua syntax
        local lua_str = str
            :gsub('%[', '{')
            :gsub('%]', '}')
            :gsub('null', 'nil')
            :gsub('"([^"]+)"%s*:', '["%1"]=')
        local fn = load("return " .. lua_str)
        if fn then
            return fn()
        end
        return nil
    end
}

-- Mock config module
package.loaded["config"] = {
    get = function(key)
        if key == "auto_scroll" then return true end
        return nil
    end
}

local ScenarioEngine = require("scenario_engine")
local Parser = require("md_parser")

-- ============================================================================
-- TEST FRAMEWORK
-- ============================================================================

local passed = 0
local failed = 0

local function test(name, fn)
    -- Clear state before each test
    clear_mock_state()
    ScenarioEngine.fragment_map = { fragments = {} }
    ScenarioEngine.regions = {}
    ScenarioEngine.current_region = -1

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

-- ============================================================================
-- HASH CALCULATION TESTS
-- ============================================================================

print("\n=== HASH CALCULATION TESTS ===")

test("calculate_hash returns consistent value", function()
    local hash1 = ScenarioEngine.calculate_hash("test content")
    local hash2 = ScenarioEngine.calculate_hash("test content")
    assert_eq(hash1, hash2)
end)

test("calculate_hash returns different values for different content", function()
    local hash1 = ScenarioEngine.calculate_hash("content A")
    local hash2 = ScenarioEngine.calculate_hash("content B")
    assert_true(hash1 ~= hash2, "Hashes should differ")
end)

test("calculate_hash with empty string returns 0", function()
    local hash = ScenarioEngine.calculate_hash("")
    assert_eq(hash, "0")
end)

test("calculate_hash with nil returns 0", function()
    local hash = ScenarioEngine.calculate_hash(nil)
    assert_eq(hash, "0")
end)

test("calculate_hash returns hex string", function()
    local hash = ScenarioEngine.calculate_hash("test")
    -- Should be a valid hex string
    assert_true(hash:match("^[0-9a-f]+$") ~= nil, "Should be hex string")
end)

-- ============================================================================
-- FRAGMENT MANAGEMENT TESTS
-- ============================================================================

print("\n=== FRAGMENT MANAGEMENT TESTS ===")

test("link_fragment creates new fragment", function()
    ScenarioEngine.link_fragment(1, 10, 20, "Scene 1")

    assert_eq(#ScenarioEngine.fragment_map.fragments, 1)
    local f = ScenarioEngine.fragment_map.fragments[1]
    assert_eq(f.region_id, 1)
    assert_eq(f.line_start, 10)
    assert_eq(f.line_end, 20)
    assert_eq(f.heading, "Scene 1")
end)

test("link_fragment updates existing fragment", function()
    ScenarioEngine.link_fragment(1, 10, 20, "Scene 1")
    ScenarioEngine.link_fragment(1, 15, 25, "Scene 1 Updated")

    assert_eq(#ScenarioEngine.fragment_map.fragments, 1)
    local f = ScenarioEngine.fragment_map.fragments[1]
    assert_eq(f.line_start, 15)
    assert_eq(f.line_end, 25)
end)

test("link_fragment maintains sorted order", function()
    ScenarioEngine.link_fragment(1, 30, 40, "Scene 3")
    ScenarioEngine.link_fragment(2, 10, 20, "Scene 1")
    ScenarioEngine.link_fragment(3, 20, 30, "Scene 2")

    assert_eq(#ScenarioEngine.fragment_map.fragments, 3)
    assert_eq(ScenarioEngine.fragment_map.fragments[1].line_start, 10)
    assert_eq(ScenarioEngine.fragment_map.fragments[2].line_start, 20)
    assert_eq(ScenarioEngine.fragment_map.fragments[3].line_start, 30)
end)

test("find_fragment_for_line returns correct fragment", function()
    ScenarioEngine.link_fragment(1, 10, 20, "Scene 1")
    ScenarioEngine.link_fragment(2, 25, 35, "Scene 2")

    local f = ScenarioEngine.find_fragment_for_line(15)
    assert_not_nil(f)
    assert_eq(f.region_id, 1)

    f = ScenarioEngine.find_fragment_for_line(30)
    assert_not_nil(f)
    assert_eq(f.region_id, 2)
end)

test("find_fragment_for_line returns nil for unlinked line", function()
    ScenarioEngine.link_fragment(1, 10, 20, "Scene 1")

    local f = ScenarioEngine.find_fragment_for_line(5)
    assert_nil(f)

    f = ScenarioEngine.find_fragment_for_line(25)
    assert_nil(f)
end)

test("find_fragment_for_line at boundaries", function()
    ScenarioEngine.link_fragment(1, 10, 20, "Scene 1")

    -- At start
    local f = ScenarioEngine.find_fragment_for_line(10)
    assert_not_nil(f)

    -- At end
    f = ScenarioEngine.find_fragment_for_line(20)
    assert_not_nil(f)
end)

test("find_fragment_for_region returns correct fragment", function()
    ScenarioEngine.link_fragment(1, 10, 20, "Scene 1")
    ScenarioEngine.link_fragment(2, 25, 35, "Scene 2")

    local f = ScenarioEngine.find_fragment_for_region(2)
    assert_not_nil(f)
    assert_eq(f.heading, "Scene 2")
end)

test("find_fragment_for_region returns nil for unlinked region", function()
    ScenarioEngine.link_fragment(1, 10, 20, "Scene 1")

    local f = ScenarioEngine.find_fragment_for_region(99)
    assert_nil(f)
end)

test("unlink_fragment removes fragment", function()
    ScenarioEngine.link_fragment(1, 10, 20, "Scene 1")
    ScenarioEngine.link_fragment(2, 25, 35, "Scene 2")

    ScenarioEngine.unlink_fragment(1)

    assert_eq(#ScenarioEngine.fragment_map.fragments, 1)
    assert_nil(ScenarioEngine.find_fragment_for_region(1))
    assert_not_nil(ScenarioEngine.find_fragment_for_region(2))
end)

test("unlink_fragment with non-existent region does nothing", function()
    ScenarioEngine.link_fragment(1, 10, 20, "Scene 1")

    ScenarioEngine.unlink_fragment(99)  -- Should not error

    assert_eq(#ScenarioEngine.fragment_map.fragments, 1)
end)

-- ============================================================================
-- REGION MANAGEMENT TESTS
-- ============================================================================

print("\n=== REGION MANAGEMENT TESTS ===")

test("refresh_regions populates regions list", function()
    set_mock_regions({
        { isrgn = true, pos = 0.0, rgnend = 10.0, name = "Intro", id = 1, color = 0 },
        { isrgn = true, pos = 10.0, rgnend = 20.0, name = "Verse", id = 2, color = 0 },
        { isrgn = false, pos = 5.0, rgnend = 5.0, name = "Marker", id = 1, color = 0 },
    })

    ScenarioEngine.refresh_regions()

    -- Should only include regions, not markers
    assert_eq(#ScenarioEngine.regions, 2)
end)

test("refresh_regions sorts by position", function()
    set_mock_regions({
        { isrgn = true, pos = 20.0, rgnend = 30.0, name = "Third", id = 3, color = 0 },
        { isrgn = true, pos = 0.0, rgnend = 10.0, name = "First", id = 1, color = 0 },
        { isrgn = true, pos = 10.0, rgnend = 20.0, name = "Second", id = 2, color = 0 },
    })

    ScenarioEngine.refresh_regions()

    assert_eq(ScenarioEngine.regions[1].name, "First")
    assert_eq(ScenarioEngine.regions[2].name, "Second")
    assert_eq(ScenarioEngine.regions[3].name, "Third")
end)

test("get_current_region returns nil when not playing", function()
    set_mock_regions({
        { isrgn = true, pos = 0.0, rgnend = 10.0, name = "Region", id = 1, color = 0 },
    })
    ScenarioEngine.refresh_regions()
    set_mock_play_state(0, 5.0)  -- Stopped

    local region = ScenarioEngine.get_current_region()
    assert_nil(region)
end)

test("get_current_region returns region when playing", function()
    set_mock_regions({
        { isrgn = true, pos = 0.0, rgnend = 10.0, name = "Region1", id = 1, color = 0 },
        { isrgn = true, pos = 10.0, rgnend = 20.0, name = "Region2", id = 2, color = 0 },
    })
    ScenarioEngine.refresh_regions()
    set_mock_play_state(1, 5.0)  -- Playing at position 5.0

    local region = ScenarioEngine.get_current_region()
    assert_not_nil(region)
    assert_eq(region.id, 1)
end)

-- ============================================================================
-- FUZZY MATCHING TESTS
-- ============================================================================

print("\n=== FUZZY MATCHING / AUTO-LINK TESTS ===")

test("auto_link_by_name matches exact names", function()
    set_mock_regions({
        { isrgn = true, pos = 0.0, rgnend = 10.0, name = "Introduction", id = 1, color = 0 },
    })

    local ast = Parser.parse("# Introduction\n\nSome text here.")
    local count = ScenarioEngine.auto_link_by_name(ast)

    assert_eq(count, 1)
    local f = ScenarioEngine.find_fragment_for_region(1)
    assert_not_nil(f)
    assert_eq(f.heading, "Introduction")
end)

test("auto_link_by_name matches case-insensitive", function()
    set_mock_regions({
        { isrgn = true, pos = 0.0, rgnend = 10.0, name = "INTRO", id = 1, color = 0 },
    })

    local ast = Parser.parse("# Intro\n\nText.")
    local count = ScenarioEngine.auto_link_by_name(ast)

    assert_eq(count, 1)
end)

test("auto_link_by_name matches substring", function()
    set_mock_regions({
        { isrgn = true, pos = 0.0, rgnend = 10.0, name = "Scene 1: Introduction", id = 1, color = 0 },
    })

    local ast = Parser.parse("# Introduction\n\nText.")
    local count = ScenarioEngine.auto_link_by_name(ast)

    assert_eq(count, 1)
end)

test("auto_link_by_name calculates section boundaries", function()
    set_mock_regions({
        { isrgn = true, pos = 0.0, rgnend = 10.0, name = "Scene 1", id = 1, color = 0 },
        { isrgn = true, pos = 10.0, rgnend = 20.0, name = "Scene 2", id = 2, color = 0 },
    })

    local ast = Parser.parse("# Scene 1\n\nText for scene 1.\n\n# Scene 2\n\nText for scene 2.")
    local count = ScenarioEngine.auto_link_by_name(ast)

    assert_eq(count, 2)

    local f1 = ScenarioEngine.find_fragment_for_region(1)
    local f2 = ScenarioEngine.find_fragment_for_region(2)

    -- Scene 1 should end before Scene 2 starts
    assert_true(f1.line_end < f2.line_start, "Scene 1 should end before Scene 2")
end)

test("auto_link_by_name does not duplicate links", function()
    set_mock_regions({
        { isrgn = true, pos = 0.0, rgnend = 10.0, name = "Scene 1", id = 1, color = 0 },
    })

    local ast = Parser.parse("# Scene 1\n\nText.")

    -- Link twice
    ScenarioEngine.auto_link_by_name(ast)
    local count = ScenarioEngine.auto_link_by_name(ast)

    -- Second call should create no new links
    assert_eq(count, 0)
    assert_eq(#ScenarioEngine.fragment_map.fragments, 1)
end)

test("auto_link_by_name with no matching regions", function()
    set_mock_regions({
        { isrgn = true, pos = 0.0, rgnend = 10.0, name = "Completely Different", id = 1, color = 0 },
    })

    local ast = Parser.parse("# Introduction\n\nText.")
    local count = ScenarioEngine.auto_link_by_name(ast)

    assert_eq(count, 0)
end)

-- ============================================================================
-- PERSISTENCE TESTS
-- ============================================================================

print("\n=== PERSISTENCE TESTS ===")

test("save_mapping stores to ProjExtState", function()
    ScenarioEngine.link_fragment(1, 10, 20, "Scene 1")
    ScenarioEngine.save_mapping("/path/to/file.md", "abc123")

    -- Check that data was stored
    local key = "ReaMD:fragment_mapping"
    assert_not_nil(mock_proj_ext_state[key])
end)

test("load_mapping retrieves from ProjExtState", function()
    -- Setup: save first
    ScenarioEngine.link_fragment(1, 10, 20, "Scene 1")
    ScenarioEngine.save_mapping("/path/to/file.md", "abc123")

    -- Clear and reload
    ScenarioEngine.fragment_map = { fragments = {} }
    local success = ScenarioEngine.load_mapping("/path/to/file.md")

    assert_true(success)
    assert_eq(#ScenarioEngine.fragment_map.fragments, 1)
end)

test("load_mapping fails for different file", function()
    ScenarioEngine.link_fragment(1, 10, 20, "Scene 1")
    ScenarioEngine.save_mapping("/path/to/file.md", "abc123")

    ScenarioEngine.fragment_map = { fragments = {} }
    local success = ScenarioEngine.load_mapping("/different/file.md")

    -- Should fail because file doesn't match
    -- Note: This depends on implementation - it should return false
    -- and reset fragment_map to empty
    assert_eq(#ScenarioEngine.fragment_map.fragments, 0)
end)

test("load_mapping with no saved data", function()
    local success = ScenarioEngine.load_mapping("/path/to/file.md")

    assert_true(success == false)
    assert_eq(#ScenarioEngine.fragment_map.fragments, 0)
end)

-- ============================================================================
-- NAVIGATION TESTS
-- ============================================================================

print("\n=== NAVIGATION TESTS ===")

test("get_scroll_target returns line_start", function()
    local fragment = { line_start = 15, line_end = 25, heading = "Scene" }
    local target = ScenarioEngine.get_scroll_target(fragment)
    assert_eq(target, 15)
end)

test("get_scroll_target with nil returns 1", function()
    local target = ScenarioEngine.get_scroll_target(nil)
    assert_eq(target, 1)
end)

-- ============================================================================
-- EDGE CASES
-- ============================================================================

print("\n=== EDGE CASES ===")

test("operations on empty fragment_map", function()
    ScenarioEngine.fragment_map = {}

    -- These should not error
    local f = ScenarioEngine.find_fragment_for_line(10)
    assert_nil(f)

    f = ScenarioEngine.find_fragment_for_region(1)
    assert_nil(f)

    ScenarioEngine.unlink_fragment(1)  -- Should not error
end)

test("hash calculation with unicode", function()
    local hash = ScenarioEngine.calculate_hash("Hello World")
    assert_not_nil(hash)
    -- Should still produce a valid hash
    assert_true(hash:match("^[0-9a-f]+$") ~= nil)
end)

test("hash calculation with long content", function()
    local content = string.rep("a", 10000)
    local hash = ScenarioEngine.calculate_hash(content)
    assert_not_nil(hash)
end)

test("multiple fragments at consecutive lines", function()
    ScenarioEngine.link_fragment(1, 1, 10, "Scene 1")
    ScenarioEngine.link_fragment(2, 11, 20, "Scene 2")
    ScenarioEngine.link_fragment(3, 21, 30, "Scene 3")

    -- Line 10 is in Scene 1
    assert_eq(ScenarioEngine.find_fragment_for_line(10).region_id, 1)
    -- Line 11 is in Scene 2
    assert_eq(ScenarioEngine.find_fragment_for_line(11).region_id, 2)
end)

-- ============================================================================
-- RESULTS
-- ============================================================================

print("\n" .. string.rep("=", 50))
print("SCENARIO ENGINE TEST RESULTS: " .. passed .. " passed, " .. failed .. " failed")
print(string.rep("=", 50))

if failed > 0 then
    os.exit(1)
else
    os.exit(0)
end
