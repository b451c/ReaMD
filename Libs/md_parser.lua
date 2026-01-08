-- md_parser.lua
-- Custom Markdown parser for ReaMD project
-- Produces AST that md_renderer.lua will consume

local Parser = {}

-- ═══════════════════════════════════════════════════════════════════════════
-- NODE TYPES
-- ═══════════════════════════════════════════════════════════════════════════

Parser.NodeTypes = {
    DOCUMENT = "document",
    HEADING = "heading",
    PARAGRAPH = "paragraph",
    TEXT = "text",
    BOLD = "bold",
    ITALIC = "italic",
    CODE_INLINE = "code_inline",
    CODE_BLOCK = "code_block",
    LIST_UL = "list_ul",
    LIST_OL = "list_ol",
    LIST_ITEM = "list_item",
    BLOCKQUOTE = "blockquote",
    LINK = "link",
    HR = "hr",
    TABLE = "table",
    TABLE_ROW = "table_row",
    TABLE_CELL = "table_cell",
}

local NT = Parser.NodeTypes

-- ═══════════════════════════════════════════════════════════════════════════
-- HELPER FUNCTIONS
-- ═══════════════════════════════════════════════════════════════════════════

--- Create a new node with common properties
-- @param node_type string: Type from NodeTypes
-- @param line_start number: Starting line number
-- @param line_end number: Ending line number (optional, defaults to line_start)
-- @return table: New node
local function create_node(node_type, line_start, line_end)
    return {
        type = node_type,
        line_start = line_start,
        line_end = line_end or line_start,
    }
end

--- Create a text node
-- @param text string: Text content
-- @param line_start number: Starting line
-- @param line_end number: Ending line
-- @return table: Text node
local function create_text_node(text, line_start, line_end)
    local node = create_node(NT.TEXT, line_start, line_end)
    node.text = text
    return node
end

--- Split text into lines while preserving empty lines
-- @param text string: Text to split
-- @return table: Array of lines
local function split_lines(text)
    local lines = {}
    local pos = 1
    local len = #text

    while pos <= len do
        local line_end = text:find("\n", pos, true)
        if line_end then
            -- Include content up to (but not including) newline
            table.insert(lines, text:sub(pos, line_end - 1))
            pos = line_end + 1
        else
            -- Last line (no trailing newline)
            table.insert(lines, text:sub(pos))
            break
        end
    end

    -- Handle trailing newline (adds empty line)
    if len > 0 and text:sub(-1) == "\n" then
        table.insert(lines, "")
    end

    return lines
end

--- Check if line is empty or whitespace only
-- @param line string: Line to check
-- @return boolean: True if empty
local function is_empty_line(line)
    return line:match("^%s*$") ~= nil
end

--- Normalize line endings (CRLF -> LF)
-- @param text string: Text to normalize
-- @return string: Normalized text
local function normalize_line_endings(text)
    return text:gsub("\r\n", "\n"):gsub("\r", "\n")
end

-- ═══════════════════════════════════════════════════════════════════════════
-- INLINE PARSING
-- ═══════════════════════════════════════════════════════════════════════════

--- Find matching delimiter, respecting escapes
-- @param text string: Text to search
-- @param start number: Start position (after opening delimiter)
-- @param delimiter string: Closing delimiter to find
-- @return number|nil: Position of closing delimiter, or nil if not found
local function find_closing_delimiter(text, start, delimiter)
    local pos = start
    local len = #text
    local delim_len = #delimiter

    while pos <= len - delim_len + 1 do
        -- Check for escape
        if text:sub(pos, pos) == "\\" then
            pos = pos + 2  -- Skip escaped character
        elseif text:sub(pos, pos + delim_len - 1) == delimiter then
            return pos
        else
            pos = pos + 1
        end
    end

    return nil
end

--- Parse inline elements from text
-- @param text string: Text to parse
-- @param line_start number: Starting line number
-- @param line_end number: Ending line number
-- @return table: Array of inline nodes
local function parse_inline(text, line_start, line_end)
    local nodes = {}
    local pos = 1
    local len = #text

    -- Buffer for accumulating plain text
    local plain_text = ""

    local function flush_text()
        if #plain_text > 0 then
            table.insert(nodes, create_text_node(plain_text, line_start, line_end))
            plain_text = ""
        end
    end

    while pos <= len do
        local char = text:sub(pos, pos)
        local next_char = text:sub(pos + 1, pos + 1)

        -- Handle escapes: \* \_ \` \[ \] \( \) \\ etc.
        if char == "\\" and pos < len then
            local escaped = text:sub(pos + 1, pos + 1)
            if escaped:match("[%*%_%`%[%]%(%)\\]") then
                plain_text = plain_text .. escaped
                pos = pos + 2
            else
                -- Not a special escape, keep backslash
                plain_text = plain_text .. char
                pos = pos + 1
            end

        -- Inline code: `code`
        elseif char == "`" then
            local code_end = find_closing_delimiter(text, pos + 1, "`")
            if code_end then
                flush_text()
                local code_content = text:sub(pos + 1, code_end - 1)
                local node = create_node(NT.CODE_INLINE, line_start, line_end)
                node.text = code_content
                table.insert(nodes, node)
                pos = code_end + 1
            else
                plain_text = plain_text .. char
                pos = pos + 1
            end

        -- Bold: **text**
        elseif char == "*" and next_char == "*" then
            local bold_end = find_closing_delimiter(text, pos + 2, "**")
            if bold_end then
                flush_text()
                local bold_content = text:sub(pos + 2, bold_end - 1)
                local node = create_node(NT.BOLD, line_start, line_end)
                node.children = parse_inline(bold_content, line_start, line_end)
                table.insert(nodes, node)
                pos = bold_end + 2
            else
                plain_text = plain_text .. char
                pos = pos + 1
            end

        -- Italic: *text* (single asterisk, not preceded by another *)
        elseif char == "*" then
            local italic_end = find_closing_delimiter(text, pos + 1, "*")
            -- Make sure it's not ** (bold)
            if italic_end and text:sub(italic_end + 1, italic_end + 1) ~= "*" then
                flush_text()
                local italic_content = text:sub(pos + 1, italic_end - 1)
                local node = create_node(NT.ITALIC, line_start, line_end)
                node.children = parse_inline(italic_content, line_start, line_end)
                table.insert(nodes, node)
                pos = italic_end + 1
            else
                plain_text = plain_text .. char
                pos = pos + 1
            end

        -- Italic: _text_
        elseif char == "_" then
            local italic_end = find_closing_delimiter(text, pos + 1, "_")
            if italic_end then
                flush_text()
                local italic_content = text:sub(pos + 1, italic_end - 1)
                local node = create_node(NT.ITALIC, line_start, line_end)
                node.children = parse_inline(italic_content, line_start, line_end)
                table.insert(nodes, node)
                pos = italic_end + 1
            else
                plain_text = plain_text .. char
                pos = pos + 1
            end

        -- Link: [text](url)
        elseif char == "[" then
            -- Find closing bracket
            local bracket_end = find_closing_delimiter(text, pos + 1, "]")
            if bracket_end and text:sub(bracket_end + 1, bracket_end + 1) == "(" then
                -- Find closing parenthesis
                local paren_end = find_closing_delimiter(text, bracket_end + 2, ")")
                if paren_end then
                    flush_text()
                    local link_text = text:sub(pos + 1, bracket_end - 1)
                    local url = text:sub(bracket_end + 2, paren_end - 1)
                    local node = create_node(NT.LINK, line_start, line_end)
                    node.url = url
                    node.children = parse_inline(link_text, line_start, line_end)
                    table.insert(nodes, node)
                    pos = paren_end + 1
                else
                    plain_text = plain_text .. char
                    pos = pos + 1
                end
            else
                plain_text = plain_text .. char
                pos = pos + 1
            end

        -- Regular character
        else
            plain_text = plain_text .. char
            pos = pos + 1
        end
    end

    flush_text()
    return nodes
end

-- ═══════════════════════════════════════════════════════════════════════════
-- BLOCK PARSING
-- ═══════════════════════════════════════════════════════════════════════════

--- Detect code block start
-- @param line string: Line to check
-- @return string|nil: Language if code block starts, or nil
local function detect_code_block_start(line)
    local match = line:match("^```(%w*)%s*$")
    if match then
        return match ~= "" and match or nil, true
    end
    return nil, false
end

--- Detect code block end
-- @param line string: Line to check
-- @return boolean: True if code block ends
local function detect_code_block_end(line)
    return line:match("^```%s*$") ~= nil
end

--- Detect header
-- @param line string: Line to check
-- @return number|nil, string|nil: Level (1-6) and content, or nil if not header
local function detect_header(line)
    local hashes, content = line:match("^(#+)%s+(.*)$")
    if hashes then
        local level = #hashes
        if level >= 1 and level <= 6 then
            return level, content
        end
    end
    return nil, nil
end

--- Detect unordered list item
-- @param line string: Line to check
-- @return string|nil, number|nil: Content and indent level, or nil if not list item
local function detect_ul_item(line)
    local indent, content = line:match("^(%s*)[%*%-]%s+(.*)$")
    if content then
        return content, #indent
    end
    return nil, nil
end

--- Detect ordered list item
-- @param line string: Line to check
-- @return string|nil, number|nil, number|nil: Content, indent level, and number
local function detect_ol_item(line)
    local indent, num, content = line:match("^(%s*)(%d+)%.%s+(.*)$")
    if content then
        return content, #indent, tonumber(num)
    end
    return nil, nil, nil
end

--- Detect blockquote
-- @param line string: Line to check
-- @return string|nil: Content after >, or nil if not blockquote
local function detect_blockquote(line)
    local content = line:match("^>%s*(.*)$")
    return content
end

--- Detect horizontal rule
-- @param line string: Line to check
-- @return boolean: True if horizontal rule
local function detect_hr(line)
    return line:match("^%-%-%-+%s*$") ~= nil or line:match("^%*%*%*+%s*$") ~= nil
end

--- Detect table row (line with pipes)
-- @param line string: Line to check
-- @return boolean: True if table row
local function detect_table_row(line)
    -- Table rows start with optional whitespace, then |
    -- and contain at least one more |
    local trimmed = line:match("^%s*(.-)%s*$")
    if not trimmed or #trimmed == 0 then return false end

    -- Must start with | and contain at least 2 pipes
    if trimmed:sub(1, 1) ~= "|" then return false end

    local pipe_count = 0
    for _ in trimmed:gmatch("|") do
        pipe_count = pipe_count + 1
    end

    return pipe_count >= 2
end

--- Detect table separator row (|---|---|)
-- @param line string: Line to check
-- @return boolean: True if separator row
local function detect_table_separator(line)
    local trimmed = line:match("^%s*(.-)%s*$")
    if not trimmed then return false end

    -- Separator row: | followed by -:| patterns
    if not detect_table_row(trimmed) then return false end

    -- Remove all valid separator characters and pipes
    local check = trimmed:gsub("[|%-:%s]", "")
    return #check == 0
end

--- Parse table cells from a row
-- @param line string: Table row line
-- @param line_num number: Line number
-- @return table: Array of cell content strings
local function parse_table_cells(line, line_num)
    local cells = {}
    local trimmed = line:match("^%s*(.-)%s*$")

    -- Remove leading and trailing |
    if trimmed:sub(1, 1) == "|" then
        trimmed = trimmed:sub(2)
    end
    if trimmed:sub(-1) == "|" then
        trimmed = trimmed:sub(1, -2)
    end

    -- Split by | and trim each cell
    for cell in trimmed:gmatch("([^|]*)") do
        local cell_content = cell:match("^%s*(.-)%s*$") or ""
        table.insert(cells, cell_content)
    end

    return cells
end

--- Parse a block of lines
-- @param lines table: Array of lines
-- @return table: Document AST node
function Parser.parse_lines(lines)
    local document = create_node(NT.DOCUMENT, 1, #lines)
    document.children = {}

    local i = 1
    local num_lines = #lines

    while i <= num_lines do
        local line = lines[i]

        -- Skip empty lines at document level
        if is_empty_line(line) then
            i = i + 1

        -- Code block
        elseif line:match("^```") then
            local lang, _ = detect_code_block_start(line)
            local start_line = i
            local code_lines = {}
            i = i + 1

            -- Collect code block content until closing ```
            while i <= num_lines do
                if detect_code_block_end(lines[i]) then
                    break
                end
                table.insert(code_lines, lines[i])
                i = i + 1
            end

            local node = create_node(NT.CODE_BLOCK, start_line, i)
            node.language = lang
            node.text = table.concat(code_lines, "\n")
            table.insert(document.children, node)

            -- Skip closing ```
            if i <= num_lines then
                i = i + 1
            end

        -- Horizontal rule
        elseif detect_hr(line) then
            local node = create_node(NT.HR, i, i)
            table.insert(document.children, node)
            i = i + 1

        -- Header
        elseif detect_header(line) then
            local level, content = detect_header(line)
            local node = create_node(NT.HEADING, i, i)
            node.level = level
            node.children = parse_inline(content, i, i)
            table.insert(document.children, node)
            i = i + 1

        -- Unordered list
        elseif detect_ul_item(line) then
            local start_line = i
            local items = {}

            while i <= num_lines do
                local content, indent = detect_ul_item(lines[i])
                if content then
                    local item_node = create_node(NT.LIST_ITEM, i, i)
                    item_node.children = parse_inline(content, i, i)
                    table.insert(items, item_node)
                    i = i + 1
                elseif is_empty_line(lines[i]) then
                    -- Empty line might continue list, check next non-empty
                    local j = i + 1
                    while j <= num_lines and is_empty_line(lines[j]) do
                        j = j + 1
                    end
                    if j <= num_lines and detect_ul_item(lines[j]) then
                        i = i + 1  -- Skip empty line, continue list
                    else
                        break  -- End of list
                    end
                else
                    break  -- Non-list content
                end
            end

            local node = create_node(NT.LIST_UL, start_line, i - 1)
            node.children = items
            table.insert(document.children, node)

        -- Ordered list
        elseif detect_ol_item(line) then
            local start_line = i
            local items = {}

            while i <= num_lines do
                local content, indent, num = detect_ol_item(lines[i])
                if content then
                    local item_node = create_node(NT.LIST_ITEM, i, i)
                    item_node.children = parse_inline(content, i, i)
                    item_node.number = num
                    table.insert(items, item_node)
                    i = i + 1
                elseif is_empty_line(lines[i]) then
                    -- Empty line might continue list
                    local j = i + 1
                    while j <= num_lines and is_empty_line(lines[j]) do
                        j = j + 1
                    end
                    if j <= num_lines and detect_ol_item(lines[j]) then
                        i = i + 1  -- Skip empty line, continue list
                    else
                        break
                    end
                else
                    break
                end
            end

            local node = create_node(NT.LIST_OL, start_line, i - 1)
            node.children = items
            table.insert(document.children, node)

        -- Blockquote
        elseif detect_blockquote(line) then
            local start_line = i
            local quote_lines = {}

            while i <= num_lines do
                local content = detect_blockquote(lines[i])
                if content then
                    table.insert(quote_lines, content)
                    i = i + 1
                elseif is_empty_line(lines[i]) then
                    -- Check if blockquote continues
                    local j = i + 1
                    while j <= num_lines and is_empty_line(lines[j]) do
                        j = j + 1
                    end
                    if j <= num_lines and detect_blockquote(lines[j]) then
                        table.insert(quote_lines, "")  -- Preserve empty line in quote
                        i = i + 1
                    else
                        break
                    end
                else
                    break
                end
            end

            local node = create_node(NT.BLOCKQUOTE, start_line, i - 1)
            -- Parse blockquote content as nested markdown
            local quote_text = table.concat(quote_lines, "\n")
            local nested_ast = Parser.parse(quote_text)
            node.children = nested_ast.children
            table.insert(document.children, node)

        -- Table
        elseif detect_table_row(line) then
            local start_line = i
            local rows = {}
            local has_header = false
            local header_cells = nil

            -- First row is the header
            header_cells = parse_table_cells(lines[i], i)
            i = i + 1

            -- Check if next line is separator (makes it a proper table with header)
            if i <= num_lines and detect_table_separator(lines[i]) then
                has_header = true
                i = i + 1  -- Skip separator
            end

            -- Collect body rows
            while i <= num_lines and detect_table_row(lines[i]) do
                local cells = parse_table_cells(lines[i], i)
                local row_node = create_node(NT.TABLE_ROW, i, i)
                row_node.cells = {}
                row_node.is_header = false
                for _, cell_text in ipairs(cells) do
                    local cell_node = create_node(NT.TABLE_CELL, i, i)
                    cell_node.children = parse_inline(cell_text, i, i)
                    table.insert(row_node.cells, cell_node)
                end
                table.insert(rows, row_node)
                i = i + 1
            end

            -- Build table node
            local table_node = create_node(NT.TABLE, start_line, i - 1)
            table_node.has_header = has_header
            table_node.rows = {}

            -- Add header row if we have one
            if header_cells then
                local header_row = create_node(NT.TABLE_ROW, start_line, start_line)
                header_row.cells = {}
                header_row.is_header = true
                for _, cell_text in ipairs(header_cells) do
                    local cell_node = create_node(NT.TABLE_CELL, start_line, start_line)
                    cell_node.children = parse_inline(cell_text, start_line, start_line)
                    table.insert(header_row.cells, cell_node)
                end
                table.insert(table_node.rows, header_row)
            end

            -- Add body rows
            for _, row in ipairs(rows) do
                table.insert(table_node.rows, row)
            end

            table.insert(document.children, table_node)

        -- Paragraph (default)
        else
            local start_line = i
            local para_lines = {}

            -- Collect consecutive non-empty, non-special lines
            while i <= num_lines do
                local curr_line = lines[i]

                -- Stop conditions
                if is_empty_line(curr_line) then break end
                if curr_line:match("^```") then break end
                if detect_hr(curr_line) then break end
                if detect_header(curr_line) then break end
                if detect_ul_item(curr_line) then break end
                if detect_ol_item(curr_line) then break end
                if detect_blockquote(curr_line) then break end
                if detect_table_row(curr_line) then break end

                table.insert(para_lines, curr_line)
                i = i + 1
            end

            if #para_lines > 0 then
                local para_text = table.concat(para_lines, " ")
                local node = create_node(NT.PARAGRAPH, start_line, i - 1)
                node.children = parse_inline(para_text, start_line, i - 1)
                table.insert(document.children, node)
            end
        end
    end

    return document
end

-- ═══════════════════════════════════════════════════════════════════════════
-- PUBLIC API
-- ═══════════════════════════════════════════════════════════════════════════

--- Parse markdown text into AST
-- @param markdown_text string: Markdown text to parse
-- @return table: Document AST node
function Parser.parse(markdown_text)
    if not markdown_text or markdown_text == "" then
        local empty_doc = create_node(NT.DOCUMENT, 1, 1)
        empty_doc.children = {}
        return empty_doc
    end

    -- Pre-processing: normalize line endings
    local normalized = normalize_line_endings(markdown_text)

    -- Split into lines
    local lines = split_lines(normalized)

    -- Parse lines into AST
    return Parser.parse_lines(lines)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- CHECKPOINT: md_parser.lua COMPLETE
-- ═══════════════════════════════════════════════════════════════════════════
-- Exported:
--   Parser.parse(markdown_text) -> AST (document node with children)
--   Parser.NodeTypes = {DOCUMENT, HEADING, PARAGRAPH, TEXT, BOLD, ITALIC,
--                       CODE_INLINE, CODE_BLOCK, LIST_UL, LIST_OL, LIST_ITEM,
--                       BLOCKQUOTE, LINK, HR}
--
-- AST Node structure:
--   ALL nodes have: type, line_start, line_end
--   Container nodes have: children = {}
--   text nodes: {type="text", text="content", line_start, line_end}
--   heading: {type="heading", level=1-6, children={...}, line_start, line_end}
--   paragraph: {type="paragraph", children={...}, line_start, line_end}
--   bold/italic: {type="bold"|"italic", children={...}, line_start, line_end}
--   code_inline: {type="code_inline", text="code", line_start, line_end}
--   code_block: {type="code_block", language="lua"|nil, text="...", line_start, line_end}
--   list_ul/list_ol: {type="list_ul"|"list_ol", children={list_items}, line_start, line_end}
--   list_item: {type="list_item", children={...}, line_start, line_end}
--             (list_ol items also have: number=N)
--   blockquote: {type="blockquote", children={...}, line_start, line_end}
--   link: {type="link", url="...", children={...}, line_start, line_end}
--   hr: {type="hr", line_start, line_end}
--
-- Edge cases handled:
--   - #NoSpace is NOT a header (requires space after #)
--   - Nested formatting: **bold _and italic_** works
--   - Escaped characters: \*not bold\* -> literal asterisks
--   - Empty lines between list items -> same list
--   - Code blocks preserve content exactly (no inline parsing)
--   - Blockquotes can contain nested markdown elements
--
-- NEXT AGENT: Read this before implementing md_renderer.lua
-- ═══════════════════════════════════════════════════════════════════════════

return Parser
