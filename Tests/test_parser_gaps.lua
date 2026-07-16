-- test_parser_gaps.lua — ReaProof-authored (U7): TABLE + STRIKETHROUGH nodes,
-- implemented in md_parser.lua but absent from test_parser.lua.
-- Run standalone with: lua test_parser_gaps.lua
-- COVERS = ['md_parse_full_markdown']

package.path = package.path .. ";../Libs/?.lua"
local Parser = require("md_parser")
local NT = Parser.NodeTypes

local passed, failed = 0, 0
local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then passed = passed + 1; print("[PASS] " .. name)
    else failed = failed + 1; print("[FAIL] " .. name .. ": " .. tostring(err)) end
end
local function assert_eq(a, e, msg)
    if a ~= e then error((msg or "") .. " expected=" .. tostring(e) .. " got=" .. tostring(a), 2) end
end

local function find_first(ast, ntype)
    for _, n in ipairs(ast.children or ast) do
        if n.type == ntype then return n end
    end
end

local function cell_text(cell)
    local parts = {}
    for _, seg in ipairs(cell.children or {}) do parts[#parts + 1] = seg.text or "" end
    return table.concat(parts)
end

test("table: header + body rows with correct cell counts", function()
    local ast = Parser.parse("| A | B |\n|---|---|\n| 1 | 2 |\n| 3 | 4 |\n")
    local tbl = find_first(ast, NT.TABLE)
    assert(tbl, "no TABLE node")
    assert_eq(tbl.has_header, true, "has_header")
    assert_eq(#tbl.rows, 3, "1 header + 2 body rows")
    assert_eq(tbl.rows[1].is_header, true, "first row is header")
    assert_eq(#tbl.rows[1].cells, 2, "header cells")
    assert_eq(cell_text(tbl.rows[3].cells[2]), "4", "body cell text")
end)

test("table: escaped pipe \\| stays inside the cell (v1.1.0 fix)", function()
    local ast = Parser.parse("| A | B |\n|---|---|\n| x \\| y | z |\n")
    local tbl = find_first(ast, NT.TABLE)
    assert(tbl, "no TABLE node")
    local body = tbl.rows[2]                    -- rows[1] is the header row
    assert_eq(#body.cells, 2, "escaped pipe must not split the cell")
    assert(cell_text(body.cells[1]):find("|", 1, true),
           "literal pipe missing: " .. cell_text(body.cells[1]))
end)

test("table: line numbers recorded", function()
    local ast = Parser.parse("intro\n\n| A |\n|---|\n| 1 |\n")
    local tbl = find_first(ast, NT.TABLE)
    assert(tbl.line_start and tbl.line_start >= 3, "line_start=" .. tostring(tbl.line_start))
end)

test("strikethrough: ~~text~~ becomes a STRIKE segment", function()
    local ast = Parser.parse("normal ~~gone~~ tail\n")
    local para = find_first(ast, NT.PARAGRAPH)
    assert(para, "no paragraph")
    local found
    for _, seg in ipairs(para.children or {}) do
        if seg.strike or seg.type == NT.STRIKE then found = seg end
    end
    assert(found, "no strike segment in paragraph children")
end)

test("strikethrough: unclosed ~~ stays literal (no crash)", function()
    local ast = Parser.parse("a ~~broken tail\n")
    assert(find_first(ast, NT.PARAGRAPH), "paragraph lost on unclosed strike")
end)

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
