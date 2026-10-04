-- test_extstate_migration.lua — v1.1.1: author-prefixed ExtState sections.
-- Settings, teleprompter position and the project scenario mapping move from
-- the bare "ReaMD*" sections to "b4s1c_ReaMD*". The project section "ReaMD"
-- may also hold other scripts' data, so migration must delete only our key.
-- The ProjExtState mock follows the REAPER API: an empty key wipes the whole
-- section, an empty value deletes one key, Get returns the value size.
-- Run standalone with: lua test_extstate_migration.lua

package.path = package.path .. ";../Libs/?.lua"

local ext, proj = {}, {}
local function pk(s, k) return s .. "\0" .. k end
reaper = {
    GetExtState = function(s, k) return ext[pk(s, k)] or "" end,
    SetExtState = function(s, k, v) ext[pk(s, k)] = tostring(v) end,
    DeleteExtState = function(s, k) ext[pk(s, k)] = nil end,
    HasExtState = function(s, k) return ext[pk(s, k)] ~= nil end,
    GetProjExtState = function(_, s, k)
        local v = proj[pk(s, k)]
        if v then return #v, v end
        return 0, ""
    end,
    SetProjExtState = function(_, s, k, v)
        if k == nil or k == "" then
            for key in pairs(proj) do
                if key:sub(1, #s + 1) == s .. "\0" then proj[key] = nil end
            end
        elseif v == nil or v == "" then
            proj[pk(s, k)] = nil
        else
            proj[pk(s, k)] = v
        end
        return 0
    end,
    ShowConsoleMsg = function() end,
}

local Config = require("config")
local ScenarioEngine = require("scenario_engine")
local Teleprompter = require("teleprompter")

local passed, failed = 0, 0
local function test(name, fn)
    ext, proj = {}, {}
    local ok, err = pcall(fn)
    if ok then passed = passed + 1; print("[PASS] " .. name)
    else failed = failed + 1; print("[FAIL] " .. name .. ": " .. tostring(err)) end
end
local function assert_eq(a, e, msg)
    if a ~= e then error((msg or "") .. " expected=" .. tostring(e) .. " got=" .. tostring(a), 2) end
end

local function mapping_json(path)
    return '{"markdown_file":"' .. path .. '","fragments":[' ..
           '{"line_start":3,"line_end":3,"identifier":"Intro","item_guids":["{G1}"]}]}'
end

test("config: legacy settings move to the prefixed section", function()
    ext[pk("ReaMD_Config", "theme")] = "dark"
    ext[pk("ReaMD_Config", "font_size")] = "18"
    Config.load()
    assert_eq(Config.get("theme"), "dark", "theme migrated")
    assert_eq(Config.get("font_size"), 18, "font_size migrated")
    assert_eq(ext[pk("b4s1c_ReaMD_Config", "theme")], "dark", "stored under new section")
    assert_eq(ext[pk("ReaMD_Config", "theme")], nil, "legacy key removed")
end)

test("config: a value already in the prefixed section wins", function()
    ext[pk("ReaMD_Config", "theme")] = "dark"
    ext[pk("b4s1c_ReaMD_Config", "theme")] = "light"
    Config.load()
    assert_eq(Config.get("theme"), "light", "new section wins")
    assert_eq(ext[pk("ReaMD_Config", "theme")], nil, "legacy key removed anyway")
end)

test("config: unknown keys in the legacy section are left alone", function()
    ext[pk("ReaMD_Config", "not_ours")] = "keep"
    Config.load()
    assert_eq(ext[pk("ReaMD_Config", "not_ours")], "keep", "foreign key untouched")
end)

test("config: saves go to the prefixed section only", function()
    Config.load()
    Config.set("theme", "dark")
    Config.save()
    assert_eq(ext[pk("b4s1c_ReaMD_Config", "theme")], "dark", "saved under new section")
    assert_eq(ext[pk("ReaMD_Config", "theme")], nil, "nothing written to legacy section")
end)

test("teleprompter: legacy window position is migrated and reused", function()
    ext[pk("ReaMD_Teleprompter", "x")] = "300"
    ext[pk("ReaMD_Teleprompter", "y")] = "400"
    ext[pk("ReaMD_Teleprompter", "w")] = "700"
    ext[pk("ReaMD_Teleprompter", "h")] = "200"
    Teleprompter.load_config()
    Teleprompter.save_config()  -- writes the in-memory position back out
    assert_eq(ext[pk("b4s1c_ReaMD_Teleprompter", "x")], "300", "x carried into position")
    assert_eq(ext[pk("b4s1c_ReaMD_Teleprompter", "h")], "200", "h carried into size")
    assert_eq(ext[pk("ReaMD_Teleprompter", "x")], nil, "legacy key removed")
end)

test("scenario: legacy project mapping migrates and loads", function()
    proj[pk("ReaMD", "fragment_mapping")] = mapping_json("/doc.md")
    assert_eq(ScenarioEngine.load_mapping("/doc.md"), true, "mapping loads")
    assert_eq(ScenarioEngine.fragment_map.fragments[1].identifier, "Intro", "content")
    assert(proj[pk("b4s1c_ReaMD", "fragment_mapping")], "stored under new section")
    assert_eq(proj[pk("ReaMD", "fragment_mapping")], nil, "legacy key removed")
end)

test("scenario: other scripts' data in the shared section survives", function()
    proj[pk("ReaMD", "fragment_mapping")] = mapping_json("/doc.md")
    proj[pk("ReaMD", "notes")] = "# someone else's project notes"
    ScenarioEngine.load_mapping("/doc.md")
    assert_eq(proj[pk("ReaMD", "notes")], "# someone else's project notes",
              "migration must not wipe the shared section")
end)

test("scenario: mapping already in the prefixed section wins", function()
    proj[pk("ReaMD", "fragment_mapping")] = mapping_json("/old.md")
    proj[pk("b4s1c_ReaMD", "fragment_mapping")] = mapping_json("/doc.md")
    assert_eq(ScenarioEngine.load_mapping("/doc.md"), true, "new mapping loads")
    assert_eq(proj[pk("ReaMD", "fragment_mapping")], nil, "stale legacy key removed")
end)

test("scenario: saves go to the prefixed section only", function()
    ScenarioEngine.fragment_map = { fragments = {} }
    ScenarioEngine.save_mapping("/doc.md", "hash")
    assert(proj[pk("b4s1c_ReaMD", "fragment_mapping")], "saved under new section")
    assert_eq(proj[pk("ReaMD", "fragment_mapping")], nil, "nothing written to legacy section")
end)

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
