-- test_sidecar_config.lua — ReaProof-authored (U7): the two highest-value
-- untested pure surfaces found by the source inventory:
--   1. .reamd sidecar persistence (save_to_file/load_from_file, v2->v3
--      migration, empty no-op, legacy marker strip)
--   2. Config get/set type validation + recent-files MRU (the v1.0.3 bug class)
-- Run standalone with: lua test_sidecar_config.lua
-- COVERS = ['scenario_persistence_reamd_sidecar', 'settings_and_theme_persistence']

package.path = package.path .. ";../Libs/?.lua"

-- minimal reaper mock (pattern from test_scenario.lua)
local ext = {}
reaper = {
    GetExtState = function(s, k) return ext[s .. "/" .. k] or "" end,
    SetExtState = function(s, k, v) ext[s .. "/" .. k] = tostring(v) end,
    DeleteExtState = function(s, k) ext[s .. "/" .. k] = nil end,
    HasExtState = function(s, k) return ext[s .. "/" .. k] ~= nil end,
    GetProjExtState = function() return 0, "" end,
    SetProjExtState = function() return 0 end,
    ShowConsoleMsg = function() end,
}

local ScenarioEngine = require("scenario_engine")
local Config = require("config")

local passed, failed = 0, 0
local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then passed = passed + 1; print("[PASS] " .. name)
    else failed = failed + 1; print("[FAIL] " .. name .. ": " .. tostring(err)) end
end
local function assert_eq(a, e, msg)
    if a ~= e then error((msg or "") .. " expected=" .. tostring(e) .. " got=" .. tostring(a), 2) end
end

local TMP = os.tmpname() .. ".md"

test("sidecar: empty map is a no-op (no file written)", function()
    ScenarioEngine.fragment_map = { fragments = {} }
    assert_eq(ScenarioEngine.save_to_file(TMP), false, "empty save must refuse")
    assert_eq(io.open(TMP .. ".reamd", "r"), nil, "no sidecar file expected")
end)

test("sidecar: v3 round-trip preserves fragments and guid arrays", function()
    ScenarioEngine.fragment_map = { fragments = {
        { line_start = 3, line_end = 5, identifier = "Intro",
          category = "VO", item_guids = { "{G1}", "{G2}" } },
        { line_start = 8, line_end = 8, identifier = "Sting",
          category = "FX", item_guids = { "{G3}" } },
    } }
    assert_eq(ScenarioEngine.save_to_file(TMP), true, "save")
    ScenarioEngine.fragment_map = { fragments = {} }
    assert_eq(ScenarioEngine.load_from_file(TMP), true, "load")
    local f = ScenarioEngine.fragment_map.fragments
    assert_eq(#f, 2, "fragment count")
    assert_eq(f[1].identifier, "Intro", "identifier")
    assert_eq(#f[1].item_guids, 2, "guid array survives")
    assert_eq(f[2].item_guids[1], "{G3}", "guid content")
end)

test("sidecar: v2 file (single item_guid) migrates to guid array", function()
    local fh = io.open(TMP .. ".reamd", "w")
    fh:write('{"version":2,"markdown_file":"x.md","fragments":[' ..
             '{"line_start":1,"line_end":2,"identifier":"Old","category":"VO",' ..
             '"item_guid":"{LEGACY}"}]}')
    fh:close()
    ScenarioEngine.fragment_map = { fragments = {} }
    assert_eq(ScenarioEngine.load_from_file(TMP), true, "v2 load")
    local f = ScenarioEngine.fragment_map.fragments[1]
    assert(f.item_guids and f.item_guids[1] == "{LEGACY}",
           "v2 item_guid not migrated to item_guids array")
end)

test("sidecar: corrupted json is refused, map left intact", function()
    local fh = io.open(TMP .. ".reamd", "w"); fh:write("{not json"); fh:close()
    ScenarioEngine.fragment_map = { fragments = { { identifier = "Keep" } } }
    assert_eq(ScenarioEngine.load_from_file(TMP), false, "corrupt load must refuse")
    assert_eq(ScenarioEngine.fragment_map.fragments[1].identifier, "Keep",
              "in-memory map must survive a corrupt file")
end)

test("marker strip: legacy embedded block removed from content", function()
    local md = "# Title\n\nbody\n\n<!-- reamd-scenario:eyJ4IjoxfQ==:reamd -->\n"
    local stripped = ScenarioEngine.strip_reamd_marker(md)
    assert(not stripped:find("reamd-scenario", 1, true), "marker not stripped")
    assert(stripped:find("# Title", 1, true), "content lost")
end)

test("config: type validation rejects wrong types, keeps value", function()
    Config.load()
    Config.set("font_size", 18)
    assert_eq(Config.get("font_size"), 18, "set/get")
    local ok = pcall(Config.set, "font_size", "huge")
    assert(Config.get("font_size") == 18, "wrong-type set must not clobber")
end)

test("config: persists through ExtState round-trip (v1.0.3 bug class)", function()
    Config.set("theme", "dark")
    Config.save()
    Config.set("theme", "light")
    Config.load()
    assert_eq(Config.get("theme"), "dark", "saved value must win after load")
end)

test("config: recent files are MRU-ordered and capped at 10", function()
    for i = 1, 12 do Config.add_recent_file("/tmp/f" .. i .. ".md") end
    Config.add_recent_file("/tmp/f3.md")          -- re-add -> moves to front
    local rec = Config.get_recent_files()
    assert_eq(#rec, 10, "cap at 10")
    assert_eq(rec[1], "/tmp/f3.md", "MRU front")
end)

os.remove(TMP); os.remove(TMP .. ".reamd")
print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
