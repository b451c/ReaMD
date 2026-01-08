-- test_parser.lua
-- Unit tests for md_parser.lua
-- Run standalone with: lua test_parser.lua

-- Adjust package path to find Libs
package.path = package.path .. ";../Libs/?.lua"

local Parser = require("md_parser")
local NT = Parser.NodeTypes

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

local function assert_nil(value, msg)
    if value ~= nil then
        error((msg or "Expected nil") .. ", got " .. tostring(value))
    end
end

--- Get first child of document
local function first_child(ast)
    return ast.children and ast.children[1]
end

--- Get text content from node (recursively extracts from children)
local function get_text(node)
    if node.text then
        return node.text
    end
    if node.children then
        local parts = {}
        for _, child in ipairs(node.children) do
            table.insert(parts, get_text(child))
        end
        return table.concat(parts, "")
    end
    return ""
end

--- Check if node has a child of given type
local function has_child_type(node, node_type)
    if not node.children then return false end
    for _, child in ipairs(node.children) do
        if child.type == node_type then return true end
        if has_child_type(child, node_type) then return true end
    end
    return false
end

-- ============================================================================
-- HEADING TESTS
-- ============================================================================

print("\n=== HEADING TESTS ===")

test("Header level 1", function()
    local ast = Parser.parse("# Header 1")
    local node = first_child(ast)
    assert_eq(node.type, NT.HEADING)
    assert_eq(node.level, 1)
    assert_eq(get_text(node), "Header 1")
end)

test("Header level 2", function()
    local ast = Parser.parse("## Header 2")
    local node = first_child(ast)
    assert_eq(node.type, NT.HEADING)
    assert_eq(node.level, 2)
    assert_eq(get_text(node), "Header 2")
end)

test("Header level 3", function()
    local ast = Parser.parse("### Header 3")
    local node = first_child(ast)
    assert_eq(node.type, NT.HEADING)
    assert_eq(node.level, 3)
end)

test("Header level 4", function()
    local ast = Parser.parse("#### Header 4")
    local node = first_child(ast)
    assert_eq(node.type, NT.HEADING)
    assert_eq(node.level, 4)
end)

test("Header level 5", function()
    local ast = Parser.parse("##### Header 5")
    local node = first_child(ast)
    assert_eq(node.type, NT.HEADING)
    assert_eq(node.level, 5)
end)

test("Header level 6", function()
    local ast = Parser.parse("###### Header 6")
    local node = first_child(ast)
    assert_eq(node.type, NT.HEADING)
    assert_eq(node.level, 6)
end)

test("#NoSpace is NOT a header (requires space after #)", function()
    local ast = Parser.parse("#NoSpace")
    local node = first_child(ast)
    assert_eq(node.type, NT.PARAGRAPH, "#NoSpace should be paragraph")
    assert_eq(get_text(node), "#NoSpace")
end)

test("##NoSpace is NOT a header", function()
    local ast = Parser.parse("##NoSpace")
    local node = first_child(ast)
    assert_eq(node.type, NT.PARAGRAPH)
end)

-- ============================================================================
-- INLINE FORMATTING TESTS
-- ============================================================================

print("\n=== INLINE FORMATTING TESTS ===")

test("Bold with **", function()
    local ast = Parser.parse("**bold**")
    local node = first_child(ast)
    assert_eq(node.type, NT.PARAGRAPH)
    assert_true(has_child_type(node, NT.BOLD))
    assert_eq(get_text(node), "bold")
end)

test("Italic with *", function()
    local ast = Parser.parse("*italic*")
    local node = first_child(ast)
    assert_eq(node.type, NT.PARAGRAPH)
    assert_true(has_child_type(node, NT.ITALIC))
    assert_eq(get_text(node), "italic")
end)

test("Italic with _", function()
    local ast = Parser.parse("_also italic_")
    local node = first_child(ast)
    assert_true(has_child_type(node, NT.ITALIC))
    assert_eq(get_text(node), "also italic")
end)

test("Inline code with `", function()
    local ast = Parser.parse("`code`")
    local node = first_child(ast)
    assert_true(has_child_type(node, NT.CODE_INLINE))
end)

test("Escaped asterisks are literal", function()
    local ast = Parser.parse("\\*escaped\\*")
    local node = first_child(ast)
    assert_eq(node.type, NT.PARAGRAPH)
    assert_eq(get_text(node), "*escaped*")
end)

test("Escaped backslash", function()
    local ast = Parser.parse("\\\\backslash")
    local node = first_child(ast)
    assert_eq(get_text(node), "\\backslash")
end)

test("Nested bold and italic: **bold _and italic_**", function()
    local ast = Parser.parse("**bold _and italic_**")
    local node = first_child(ast)
    assert_true(has_child_type(node, NT.BOLD))
    assert_true(has_child_type(node, NT.ITALIC))
end)

test("Mixed text with bold", function()
    local ast = Parser.parse("before **bold** after")
    local node = first_child(ast)
    assert_eq(get_text(node), "before bold after")
end)

-- ============================================================================
-- LIST TESTS
-- ============================================================================

print("\n=== LIST TESTS ===")

test("Unordered list with -", function()
    local ast = Parser.parse("- item 1\n- item 2")
    local node = first_child(ast)
    assert_eq(node.type, NT.LIST_UL)
    assert_eq(#node.children, 2, "Should have 2 items")
end)

test("Unordered list with *", function()
    local ast = Parser.parse("* item 1\n* item 2")
    local node = first_child(ast)
    assert_eq(node.type, NT.LIST_UL)
    assert_eq(#node.children, 2)
end)

test("Ordered list", function()
    local ast = Parser.parse("1. first\n2. second")
    local node = first_child(ast)
    assert_eq(node.type, NT.LIST_OL)
    assert_eq(#node.children, 2)
end)

test("Ordered list preserves numbers", function()
    local ast = Parser.parse("1. first\n2. second\n3. third")
    local node = first_child(ast)
    assert_eq(node.children[1].number, 1)
    assert_eq(node.children[2].number, 2)
    assert_eq(node.children[3].number, 3)
end)

test("List with inline formatting", function()
    local ast = Parser.parse("- **bold item**\n- *italic item*")
    local node = first_child(ast)
    assert_eq(node.type, NT.LIST_UL)
    assert_true(has_child_type(node.children[1], NT.BOLD))
    assert_true(has_child_type(node.children[2], NT.ITALIC))
end)

-- ============================================================================
-- CODE BLOCK TESTS
-- ============================================================================

print("\n=== CODE BLOCK TESTS ===")

test("Code block with language", function()
    local ast = Parser.parse("```lua\ncode here\n```")
    local node = first_child(ast)
    assert_eq(node.type, NT.CODE_BLOCK)
    assert_eq(node.language, "lua")
    assert_eq(node.text, "code here")
end)

test("Code block without language", function()
    local ast = Parser.parse("```\nno lang\n```")
    local node = first_child(ast)
    assert_eq(node.type, NT.CODE_BLOCK)
    assert_nil(node.language)
    assert_eq(node.text, "no lang")
end)

test("Code block preserves content exactly", function()
    local content = "  indented\n\n  with blank line"
    local ast = Parser.parse("```\n" .. content .. "\n```")
    local node = first_child(ast)
    assert_eq(node.text, content)
end)

test("Code block with multiple languages", function()
    local ast = Parser.parse("```javascript\nconst x = 1;\n```")
    local node = first_child(ast)
    assert_eq(node.language, "javascript")
end)

-- ============================================================================
-- LINK TESTS
-- ============================================================================

print("\n=== LINK TESTS ===")

test("Basic link", function()
    local ast = Parser.parse("[text](url)")
    local node = first_child(ast)
    assert_true(has_child_type(node, NT.LINK))
    -- Find the link node
    local link = node.children[1]
    assert_eq(link.type, NT.LINK)
    assert_eq(link.url, "url")
    assert_eq(get_text(link), "text")
end)

test("Link with full URL", function()
    local ast = Parser.parse("[GitHub](https://github.com)")
    local node = first_child(ast)
    local link = node.children[1]
    assert_eq(link.url, "https://github.com")
end)

test("Link with formatted text", function()
    local ast = Parser.parse("[**bold link**](url)")
    local node = first_child(ast)
    local link = node.children[1]
    assert_true(has_child_type(link, NT.BOLD))
end)

-- ============================================================================
-- HORIZONTAL RULE TESTS
-- ============================================================================

print("\n=== HORIZONTAL RULE TESTS ===")

test("HR with ---", function()
    local ast = Parser.parse("---")
    local node = first_child(ast)
    assert_eq(node.type, NT.HR)
end)

test("HR with ***", function()
    local ast = Parser.parse("***")
    local node = first_child(ast)
    assert_eq(node.type, NT.HR)
end)

test("HR with ----", function()
    local ast = Parser.parse("----")
    local node = first_child(ast)
    assert_eq(node.type, NT.HR)
end)

-- ============================================================================
-- BLOCKQUOTE TESTS
-- ============================================================================

print("\n=== BLOCKQUOTE TESTS ===")

test("Single line blockquote", function()
    local ast = Parser.parse("> quoted text")
    local node = first_child(ast)
    assert_eq(node.type, NT.BLOCKQUOTE)
end)

test("Multi-line blockquote", function()
    local ast = Parser.parse("> line 1\n> line 2")
    local node = first_child(ast)
    assert_eq(node.type, NT.BLOCKQUOTE)
end)

test("Blockquote with formatting", function()
    local ast = Parser.parse("> **bold** in quote")
    local node = first_child(ast)
    assert_eq(node.type, NT.BLOCKQUOTE)
    assert_true(has_child_type(node, NT.BOLD))
end)

-- ============================================================================
-- PARAGRAPH AND TEXT TESTS
-- ============================================================================

print("\n=== PARAGRAPH AND TEXT TESTS ===")

test("Plain paragraph", function()
    local ast = Parser.parse("This is plain text.")
    local node = first_child(ast)
    assert_eq(node.type, NT.PARAGRAPH)
    assert_eq(get_text(node), "This is plain text.")
end)

test("Multi-line paragraph (soft breaks)", function()
    local ast = Parser.parse("Line 1\nLine 2")
    local node = first_child(ast)
    assert_eq(node.type, NT.PARAGRAPH)
    -- Lines are joined with space
    assert_eq(get_text(node), "Line 1 Line 2")
end)

test("Empty document", function()
    local ast = Parser.parse("")
    assert_eq(ast.type, NT.DOCUMENT)
    assert_eq(#ast.children, 0)
end)

test("Whitespace only document", function()
    local ast = Parser.parse("   \n\n   ")
    assert_eq(ast.type, NT.DOCUMENT)
    assert_eq(#ast.children, 0)
end)

-- ============================================================================
-- LINE NUMBER TESTS
-- ============================================================================

print("\n=== LINE NUMBER TESTS ===")

test("Single line has correct line_start/line_end", function()
    local ast = Parser.parse("# Header")
    local node = first_child(ast)
    assert_eq(node.line_start, 1)
    assert_eq(node.line_end, 1)
end)

test("Multi-line block has correct line range", function()
    local ast = Parser.parse("```\ncode\nmore\n```")
    local node = first_child(ast)
    assert_eq(node.line_start, 1)
    assert_eq(node.line_end, 4)
end)

test("Second element has correct line number", function()
    local ast = Parser.parse("# First\n\n## Second")
    local node = ast.children[2]
    assert_eq(node.line_start, 3)
end)

-- ============================================================================
-- EDGE CASES
-- ============================================================================

print("\n=== EDGE CASES ===")

test("Unclosed bold is literal", function()
    local ast = Parser.parse("**unclosed")
    local node = first_child(ast)
    assert_eq(get_text(node), "**unclosed")
end)

test("Unclosed italic is literal", function()
    local ast = Parser.parse("*unclosed")
    local node = first_child(ast)
    assert_eq(get_text(node), "*unclosed")
end)

test("Unclosed inline code is literal", function()
    local ast = Parser.parse("`unclosed")
    local node = first_child(ast)
    assert_eq(get_text(node), "`unclosed")
end)

test("Unclosed link is literal", function()
    local ast = Parser.parse("[unclosed")
    local node = first_child(ast)
    assert_eq(get_text(node), "[unclosed")
end)

test("CRLF line endings are normalized", function()
    local ast = Parser.parse("# Header\r\n\r\nParagraph")
    assert_eq(#ast.children, 2)
    assert_eq(ast.children[1].type, NT.HEADING)
    assert_eq(ast.children[2].type, NT.PARAGRAPH)
end)

test("CR line endings are normalized", function()
    local ast = Parser.parse("# Header\r\rParagraph")
    assert_eq(#ast.children, 2)
end)

test("Empty code block", function()
    local ast = Parser.parse("```\n```")
    local node = first_child(ast)
    assert_eq(node.type, NT.CODE_BLOCK)
    assert_eq(node.text, "")
end)

test("Empty list item", function()
    local ast = Parser.parse("- \n- item")
    local node = first_child(ast)
    assert_eq(node.type, NT.LIST_UL)
    assert_eq(#node.children, 2)
end)

-- ============================================================================
-- COMPLEX DOCUMENT TESTS
-- ============================================================================

print("\n=== COMPLEX DOCUMENT TESTS ===")

test("Full document structure", function()
    local md = [[# Title

Some **bold** and *italic* text.

## Section

- Item 1
- Item 2

```lua
code block
```

> A quote

---

[Link](http://example.com)
]]
    local ast = Parser.parse(md)
    assert_eq(ast.type, NT.DOCUMENT)
    assert_true(#ast.children >= 7, "Should have multiple children")
end)

test("Heading followed by list", function()
    local ast = Parser.parse("# Heading\n\n- Item 1\n- Item 2")
    assert_eq(ast.children[1].type, NT.HEADING)
    assert_eq(ast.children[2].type, NT.LIST_UL)
end)

test("Multiple code blocks", function()
    local ast = Parser.parse("```lua\nfirst\n```\n\n```python\nsecond\n```")
    assert_eq(ast.children[1].type, NT.CODE_BLOCK)
    assert_eq(ast.children[1].language, "lua")
    assert_eq(ast.children[2].type, NT.CODE_BLOCK)
    assert_eq(ast.children[2].language, "python")
end)

-- ============================================================================
-- RESULTS
-- ============================================================================

print("\n" .. string.rep("=", 50))
print("PARSER TEST RESULTS: " .. passed .. " passed, " .. failed .. " failed")
print(string.rep("=", 50))

if failed > 0 then
    os.exit(1)
else
    os.exit(0)
end
