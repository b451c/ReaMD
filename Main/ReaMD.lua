-- @description ReaMD - Dockable Markdown Viewer for REAPER
-- @author b4s1c
-- @version 1.1.0
-- @changelog
--   v1.1.0 (2026-05-27)
--   + Search inside document (Ctrl+F) with next/prev navigation
--   + Cue List floating panel — sorted fragment list, click to jump
--   + Export linked fragments to REAPER regions (Scenario > Tools menu)
--   + Auto-Link by name — matches headings AND table rows against item take
--     names + region names (Scenario > Tools menu)
--   + time://HH:MM:SS links jump REAPER edit cursor on click
--   + AI Parse: model selector (Haiku/Sonnet/Opus) + better error messages
--   + AI Parse: Windows support (.bat launcher in addition to .sh)
--   + AI Parse: result preview is editable before Save As
--   + Strikethrough (~~text~~) parsing and rendering
--   + Keyboard shortcuts: Ctrl+F search, Ctrl+S save, Ctrl+O open, Ctrl+E edit
--   + Window title shows unsaved-changes asterisk
--   + Welcome screen with action buttons + recent files
--   + Font size slider in settings
--   + Auto-save scenario .reamd file on every change
--   * Fix table cells: long content now wraps to cell width instead of
--     overflowing (was the most visible rendering glitch)
--   * Fix table parsing: escaped \| and consecutive | no longer produce
--     phantom empty cells
--   * Fix code blocks: long lines now scroll horizontally
--   * Fix heading highlight height — scales with actual heading font size
--   * Link hover shows the URL as tooltip
--   * Table cells now render italic and inline code (was silently skipped)
--   v1.0.3 (2026-01-11)
--   * Fix ImGui ID conflict when recent files have same filename
--   * Fix settings (theme, etc.) not persisting after restart
--   * Redesign Light theme: better contrast, blue buttons, alternating table rows
--   * Improve scenario [+] button colors for better visibility in light theme
--   v1.0.2 (2026-01-11)
--   * Update welcome message to reflect current features
--   v1.0.1 (2026-01-10)
--   * Fix ReaPack installation - include all required files (ai_parser.lua, teleprompter.lua, ai_format_prompt.txt)
--   v1.0.0 (2026-01-08)
--   + Initial public release
--   + Full markdown rendering (headers, lists, tables, code blocks)
--   + Scenario Mode with multi-item linking
--   + Teleprompter mode with auto-scroll
--   + AI Parse feature (Claude API integration)
--   + Dark and Light themes
-- @provides
--   [main] ReaMD.lua
--   [nomain] ../Libs/ai_parser.lua
--   [nomain] ../Libs/config.lua
--   [nomain] ../Libs/json.lua
--   [nomain] ../Libs/md_parser.lua
--   [nomain] ../Libs/md_renderer.lua
--   [nomain] ../Libs/scenario_engine.lua
--   [nomain] ../Libs/teleprompter.lua
--   [nomain] ../Libs/cue_list.lua
--   [nomain] ../Libs/utils.lua
--   [data] ../prompts/ai_format_prompt.txt
-- @link GitHub https://github.com/b451c/ReaMD
-- @link Forum Thread https://forum.cockos.com/showthread.php?p=2915326
-- @screenshot https://raw.githubusercontent.com/b451c/ReaMD/main/docs/images/hero.png
-- @donation https://buymeacoffee.com/bsroczynskh
-- @about
--   # ReaMD - Markdown Viewer for REAPER
--
--   Dockable markdown viewer designed for audio production workflows.
--   Link text fragments to timeline items, use teleprompter mode for VO,
--   and format text with AI.
--
--   ## Features
--
--   **Core**
--   - Full markdown rendering (headers, lists, tables, code blocks, blockquotes)
--   - Edit mode - create and modify markdown in REAPER
--   - Dark & Light themes
--
--   **Scenario Mode**
--   - Link text fragments to timeline items
--   - Multi-item support with category colors (V/M/F/O)
--   - REAPER group awareness
--   - Playback position tracking
--
--   **Teleprompter**
--   - VO-focused display with auto-scroll
--   - Large centered text, progress indicator
--
--   **AI Parse**
--   - Convert unformatted text to markdown using Claude AI
--   - Customizable prompt template
--   - Async processing (non-blocking)
--
--   ## Requirements
--   - REAPER 7.0+
--   - ReaImGui 0.10+
--   - (Recommended) js_ReaScriptAPI, SWS Extension
--
--   ## Note
--   Tested on macOS Tahoe 26.2. Windows/Linux support expected but not verified.

-- ===============================================================================
-- SETUP: Module Loading and Path Configuration
-- ===============================================================================

local info = debug.getinfo(1, 'S')
local script_path = info.source:match('@?(.+)')
local script_dir = script_path:match('^(.+)[/\\]')
local project_dir = script_dir:match('^(.+)[/\\]')  -- Go up one level from Main/

-- Set up package path to find modules in Libs/
package.path = project_dir .. '/Libs/?.lua;' .. package.path

-- ===============================================================================
-- DEPENDENCY CHECK: ReaImGui
-- ===============================================================================

if not reaper.ImGui_CreateContext then
    reaper.MB(
        "ReaImGui extension required.\n\n" ..
        "Install via ReaPack:\n" ..
        "Extensions > ReaPack > Browse packages > ReaImGui",
        "ReaMD Error", 0
    )
    return
end

-- ===============================================================================
-- MODULE IMPORTS
-- ===============================================================================

local Utils = require('utils')
local Config = require('config')
Config.load()  -- Load saved settings from ExtState
local Parser = require('md_parser')
local Renderer = require('md_renderer')
local ScenarioEngine = require('scenario_engine')
local json = require('json')
local Teleprompter = require('teleprompter')
local AIParser = require('ai_parser')
local CueList = require('cue_list')

-- ===============================================================================
-- CONSTANTS
-- ===============================================================================

local WINDOW_TITLE = "ReaMD"
local WINDOW_FLAGS = nil  -- Set during init
local MIN_WINDOW_WIDTH = 300
local MIN_WINDOW_HEIGHT = 200

-- ===============================================================================
-- APPLICATION STATE
-- ===============================================================================

local ctx = nil  -- ReaImGui context
local fonts = {} -- Font handles

local state = {
    -- File state
    file_path = nil,
    file_name = nil,
    markdown_content = "",
    parsed_ast = nil,
    content_hash = nil,

    -- Scroll state
    scroll_y = 0,
    scroll_to_line = nil,
    highlight_lines = nil,  -- Set of active line_starts: {[line_start]=true, ...}
    clicked_link = nil,

    -- UI state
    show_settings = false,
    show_link_dialog = false,
    selected_heading = nil,
    status_message = nil,
    status_time = 0,

    -- Scenario state
    scenario_enabled = false,

    -- Edit mode (for text editing)
    edit_mode = false,
    edit_changed = false,  -- True if text was modified

    -- New file mode (for "New Markdown")
    is_new_file = false,   -- True when creating new file (always Save As on first save)

    -- Settings UI state
    show_api_key = false,  -- Toggle for API key visibility in settings

    -- In-document search (Ctrl+F)
    search_visible = false,
    search_query = "",
    search_matches = nil,          -- Array of block-line numbers
    search_idx = 0,                -- 1-based index into search_matches
    search_focus_next_frame = false,

    -- One-shot: focus the markdown editor InputText on the next frame
    -- (used after "New > Markdown" to fix "I can't type" UX).
    focus_editor_next_frame = false,
}

-- ===============================================================================
-- IN-DOCUMENT SEARCH
-- ===============================================================================

--- Map a raw line number to the line_start of the block-level AST node that
-- contains it. The renderer records positions per node, not per raw line,
-- so we need this to scroll-and-highlight a meaningful chunk.
local function find_block_line(line)
    local ast = state.parsed_ast
    if not ast or not ast.children then return line end
    for _, node in ipairs(ast.children) do
        local s = node.line_start or 1
        local e = node.line_end or s
        if line >= s and line <= e then
            return s
        end
    end
    return line
end

--- Rebuild the matches array from the current query.
local function rebuild_search_matches()
    state.search_matches = {}
    state.search_idx = 0

    local q = state.search_query
    if not q or q == "" then return end
    if not state.markdown_content or state.markdown_content == "" then return end

    local needle = q:lower()
    local line_num = 1
    -- Trailing newline ensures the last line is yielded even without one
    for line in (state.markdown_content .. "\n"):gmatch("([^\n]*)\n") do
        if line:lower():find(needle, 1, true) then
            local block_line = find_block_line(line_num)
            -- Avoid duplicates from multiple raw lines mapping to same block
            if state.search_matches[#state.search_matches] ~= block_line then
                table.insert(state.search_matches, block_line)
            end
        end
        line_num = line_num + 1
    end

    if #state.search_matches > 0 then
        state.search_idx = 1
        state.scroll_to_line = state.search_matches[1]
    end
end

local function search_next()
    local n = state.search_matches and #state.search_matches or 0
    if n == 0 then return end
    state.search_idx = (state.search_idx % n) + 1
    state.scroll_to_line = state.search_matches[state.search_idx]
end

local function search_prev()
    local n = state.search_matches and #state.search_matches or 0
    if n == 0 then return end
    state.search_idx = ((state.search_idx - 2 + n) % n) + 1
    state.scroll_to_line = state.search_matches[state.search_idx]
end

local function search_close()
    state.search_visible = false
    state.search_query = ""
    state.search_matches = nil
    state.search_idx = 0
end

local function search_open()
    state.search_visible = true
    state.search_focus_next_frame = true
end

-- ===============================================================================
-- FONT SETUP
-- ===============================================================================

-- Font sizes (set during setup, used with PushFont)
local font_sizes = {}

--- Setup fonts based on current configuration
-- ReaImGui v0.10+ API: CreateFont(family) without size, size goes to PushFont
-- @param imgui_ctx ReaImGui context
local function setup_fonts(imgui_ctx)
    local size = Config.get("font_size")

    -- Store sizes for use with PushFont(ctx, font, size)
    font_sizes.normal = size
    font_sizes.bold = size
    font_sizes.italic = size
    font_sizes.bold_italic = size
    font_sizes.h1 = math.floor(size * 1.7)
    font_sizes.h2 = math.floor(size * 1.4)
    font_sizes.h3 = math.floor(size * 1.2)
    font_sizes.code = size - 1

    -- ReaImGui v0.10+: CreateFont takes only family name
    -- Bold/italic not available as flags - use same font, different size for headers
    fonts.normal = reaper.ImGui_CreateFont('sans-serif')
    fonts.bold = reaper.ImGui_CreateFont('sans-serif')      -- Same font (no bold flag available)
    fonts.italic = reaper.ImGui_CreateFont('sans-serif')    -- Same font (no italic flag available)
    fonts.bold_italic = reaper.ImGui_CreateFont('sans-serif')
    fonts.h1 = reaper.ImGui_CreateFont('sans-serif')
    fonts.h2 = reaper.ImGui_CreateFont('sans-serif')
    fonts.h3 = reaper.ImGui_CreateFont('sans-serif')
    fonts.code = reaper.ImGui_CreateFont('monospace')

    -- Store sizes for renderer (v0.10+ passes size to PushFont)
    fonts.sizes = font_sizes

    for name, font in pairs(fonts) do
        if name ~= "sizes" then  -- Don't attach the sizes table
            reaper.ImGui_Attach(imgui_ctx, font)
        end
    end
end

--- Get font size for a font key
-- @param key string: Font key (normal, bold, h1, etc.)
-- @return number: Font size
local function get_font_size(key)
    return font_sizes[key] or font_sizes.normal
end

-- ===============================================================================
-- THEME SYSTEM
-- ===============================================================================

--- Apply theme colors to ImGui context
-- @param imgui_ctx ReaImGui context
local function apply_theme(imgui_ctx)
    local theme = Config.get("theme")

    -- Auto theme: detect from system (fallback to dark)
    if theme == "auto" then
        -- ReaImGui doesn't have system theme detection, default to dark
        theme = "dark"
    end

    if theme == "dark" then
        -- Dark theme colors (same bg for window and child to avoid visible border)
        reaper.ImGui_PushStyleColor(imgui_ctx, reaper.ImGui_Col_WindowBg(), 0x252526FF)
        reaper.ImGui_PushStyleColor(imgui_ctx, reaper.ImGui_Col_ChildBg(), 0x252526FF)
        reaper.ImGui_PushStyleColor(imgui_ctx, reaper.ImGui_Col_Text(), 0xD4D4D4FF)
        reaper.ImGui_PushStyleColor(imgui_ctx, reaper.ImGui_Col_TextDisabled(), 0x808080FF)
        reaper.ImGui_PushStyleColor(imgui_ctx, reaper.ImGui_Col_Border(), 0x3C3C3CFF)
        reaper.ImGui_PushStyleColor(imgui_ctx, reaper.ImGui_Col_FrameBg(), 0x3C3C3CFF)
        reaper.ImGui_PushStyleColor(imgui_ctx, reaper.ImGui_Col_FrameBgHovered(), 0x4C4C4CFF)
        reaper.ImGui_PushStyleColor(imgui_ctx, reaper.ImGui_Col_Button(), 0x0E639CFF)
        reaper.ImGui_PushStyleColor(imgui_ctx, reaper.ImGui_Col_ButtonHovered(), 0x1177BBFF)
        reaper.ImGui_PushStyleColor(imgui_ctx, reaper.ImGui_Col_Header(), 0x0E639CFF)
        reaper.ImGui_PushStyleColor(imgui_ctx, reaper.ImGui_Col_HeaderHovered(), 0x1177BBFF)
        reaper.ImGui_PushStyleColor(imgui_ctx, reaper.ImGui_Col_ScrollbarBg(), 0x1E1E1EFF)
        reaper.ImGui_PushStyleColor(imgui_ctx, reaper.ImGui_Col_ScrollbarGrab(), 0x4C4C4CFF)
        reaper.ImGui_PushStyleColor(imgui_ctx, reaper.ImGui_Col_PopupBg(), 0x2D2D2DFF)        -- Dark popup bg
        -- Table row backgrounds (alternating)
        reaper.ImGui_PushStyleColor(imgui_ctx, reaper.ImGui_Col_TableRowBg(), 0x00000000)      -- Transparent
        reaper.ImGui_PushStyleColor(imgui_ctx, reaper.ImGui_Col_TableRowBgAlt(), 0x2A2A2AFF)  -- Subtle alternating
        reaper.ImGui_PushStyleColor(imgui_ctx, reaper.ImGui_Col_TableBorderStrong(), 0x4A4A4AFF)
        reaper.ImGui_PushStyleColor(imgui_ctx, reaper.ImGui_Col_TableBorderLight(), 0x3A3A3AFF)
    else
        -- Light theme - professional with clear contrast
        -- Window background: clean off-white
        reaper.ImGui_PushStyleColor(imgui_ctx, reaper.ImGui_Col_WindowBg(), 0xE8E8E8FF)
        reaper.ImGui_PushStyleColor(imgui_ctx, reaper.ImGui_Col_ChildBg(), 0xE8E8E8FF)
        -- Text: dark for readability
        reaper.ImGui_PushStyleColor(imgui_ctx, reaper.ImGui_Col_Text(), 0x1A1A1AFF)
        reaper.ImGui_PushStyleColor(imgui_ctx, reaper.ImGui_Col_TextDisabled(), 0x6A6A6AFF)
        -- Borders: visible but subtle
        reaper.ImGui_PushStyleColor(imgui_ctx, reaper.ImGui_Col_Border(), 0x9A9A9AFF)
        -- Frames (inputs): white with clear border
        reaper.ImGui_PushStyleColor(imgui_ctx, reaper.ImGui_Col_FrameBg(), 0xFFFFFFFF)
        reaper.ImGui_PushStyleColor(imgui_ctx, reaper.ImGui_Col_FrameBgHovered(), 0xF5F5F5FF)
        -- Buttons: blue accent (matches dark theme)
        reaper.ImGui_PushStyleColor(imgui_ctx, reaper.ImGui_Col_Button(), 0x4A90D9FF)
        reaper.ImGui_PushStyleColor(imgui_ctx, reaper.ImGui_Col_ButtonHovered(), 0x5BA0E9FF)
        -- Headers (selections)
        reaper.ImGui_PushStyleColor(imgui_ctx, reaper.ImGui_Col_Header(), 0xD0E0F0FF)
        reaper.ImGui_PushStyleColor(imgui_ctx, reaper.ImGui_Col_HeaderHovered(), 0xE0F0FFFF)
        -- Scrollbar
        reaper.ImGui_PushStyleColor(imgui_ctx, reaper.ImGui_Col_ScrollbarBg(), 0xD8D8D8FF)
        reaper.ImGui_PushStyleColor(imgui_ctx, reaper.ImGui_Col_ScrollbarGrab(), 0xA0A0A0FF)
        -- Popup
        reaper.ImGui_PushStyleColor(imgui_ctx, reaper.ImGui_Col_PopupBg(), 0xF5F5F5FF)
        -- Table row backgrounds (alternating)
        reaper.ImGui_PushStyleColor(imgui_ctx, reaper.ImGui_Col_TableRowBg(), 0xFFFFFF00)     -- Transparent (use default)
        reaper.ImGui_PushStyleColor(imgui_ctx, reaper.ImGui_Col_TableRowBgAlt(), 0xF0F0F0FF) -- Subtle alternating
        reaper.ImGui_PushStyleColor(imgui_ctx, reaper.ImGui_Col_TableBorderStrong(), 0xB0B0B0FF)
        reaper.ImGui_PushStyleColor(imgui_ctx, reaper.ImGui_Col_TableBorderLight(), 0xD0D0D0FF)
    end
end

-- Track number of pushed style colors for cleanup
local THEME_COLOR_COUNT = 18

--- Remove theme colors (call at end of frame)
local function pop_theme()
    reaper.ImGui_PopStyleColor(ctx, THEME_COLOR_COUNT)
end

-- ===============================================================================
-- STATUS MESSAGE SYSTEM
-- ===============================================================================

--- Show a temporary status message
-- @param message string: Message to display
-- @param duration number: Duration in seconds (default 3)
local function show_status(message, duration)
    state.status_message = message
    state.status_time = reaper.time_precise() + (duration or 3)
end

--- Clear status message if expired
local function update_status()
    if state.status_message and reaper.time_precise() > state.status_time then
        state.status_message = nil
    end
end

-- ===============================================================================
-- FILE OPERATIONS
-- ===============================================================================

--- Load a markdown file and parse it
-- @param path string: Path to markdown file
-- @return boolean: True if loaded successfully
local function load_markdown_file(path)
    if not path then
        return false
    end

    local normalized_path = Utils.normalize_path(path)

    -- Read file contents
    local content, err = Utils.read_file(normalized_path)
    if not content then
        reaper.MB("Cannot open file:\n" .. (err or "Unknown error"), "ReaMD Error", 0)
        return false
    end

    -- Check if file has embedded scenario data
    local has_scenario_data = ScenarioEngine.file_has_scenario_data(normalized_path)

    -- Strip reamd marker from content before parsing (so it doesn't show in viewer)
    local clean_content = ScenarioEngine.strip_reamd_marker(content)

    -- Update state
    state.file_path = normalized_path
    state.file_name = Utils.get_filename(normalized_path)
    state.markdown_content = clean_content  -- Use clean content for display
    state.content_hash = ScenarioEngine.calculate_hash(clean_content)

    -- Parse markdown (without reamd marker)
    state.parsed_ast = Parser.parse(clean_content)

    -- Reset scroll
    state.scroll_y = 0
    state.scroll_to_line = nil
    state.highlight_lines = nil

    -- Try to load scenario from file first, then from ExtState
    local loaded_from_file = false
    if has_scenario_data then
        loaded_from_file = ScenarioEngine.load_from_file(normalized_path)
    end

    if not loaded_from_file then
        -- Fallback to ExtState
        ScenarioEngine.load_mapping(normalized_path)
    end

    ScenarioEngine.refresh_regions()

    -- Auto-enable scenario mode if file has scenario data
    if has_scenario_data and loaded_from_file then
        state.scenario_enabled = true
        ScenarioEngine.init()
        show_status("Loaded: " .. state.file_name .. " (Scenario ON)")
    else
        show_status("Loaded: " .. state.file_name)
    end

    -- Save last directory and add to recent files
    Config.set("last_directory", Utils.get_directory(normalized_path))
    Config.add_recent_file(normalized_path)
    Config.save()

    -- Reset edit state
    state.edit_changed = false

    return true
end

--- Save markdown file after editing
-- @param force_save_as boolean: If true, always show Save As dialog
-- @return boolean: True if saved successfully
local function save_markdown_file(force_save_as)
    if not state.markdown_content then
        show_status("No content to save")
        return false
    end

    -- For new files or force, show Save As dialog
    if state.is_new_file or not state.file_path or force_save_as then
        local last_dir = Config.get("last_directory")
        if not last_dir or last_dir == "" then
            -- Try to get project directory
            local proj_path = reaper.GetProjectPath("")
            if proj_path and proj_path ~= "" then
                last_dir = proj_path
            else
                last_dir = ""
            end
        end

        -- Try JS extension for save dialog first
        local retval, filename
        if reaper.JS_Dialog_BrowseForSaveFile then
            retval, filename = reaper.JS_Dialog_BrowseForSaveFile(
                "Save Markdown File",
                last_dir,
                state.file_name or "untitled.md",
                "Markdown files (*.md)\0*.md\0All files (*.*)\0*.*\0"
            )
        else
            -- Fallback: use GetUserFileNameForRead (not ideal but works)
            retval, filename = reaper.GetUserFileNameForRead(
                last_dir,
                "Save As (select or type filename)",
                "*.md"
            )
        end

        if not retval or not filename or filename == "" then
            show_status("Save cancelled")
            return false
        end

        -- Ensure .md extension
        if not filename:match("%.md$") and not filename:match("%.markdown$") then
            filename = filename .. ".md"
        end

        state.file_path = filename
        state.file_name = Utils.get_filename(filename)
        state.is_new_file = false

        -- Save directory for next time
        Config.set("last_directory", Utils.get_directory(filename))
        Config.add_recent_file(filename)
        Config.save()
    end

    -- Write to file
    local f = io.open(state.file_path, "w")
    if not f then
        reaper.MB("Cannot save file:\n" .. state.file_path, "ReaMD Error", 0)
        return false
    end

    f:write(state.markdown_content)
    f:close()

    -- Re-parse the content
    state.parsed_ast = Parser.parse(state.markdown_content)
    state.content_hash = ScenarioEngine.calculate_hash(state.markdown_content)

    -- Clear edit changed flag
    state.edit_changed = false

    show_status("Saved: " .. state.file_name)
    return true
end

--- Open file dialog for selecting a markdown file
local function open_file_dialog()
    local last_dir = Config.get("last_directory")
    if not last_dir or last_dir == "" then
        last_dir = ""
    end

    local retval, filename = reaper.GetUserFileNameForRead(
        last_dir,
        "Open Markdown File",
        "*.md;*.markdown"
    )

    if retval then
        load_markdown_file(filename)
    end
end

-- ===============================================================================
-- LINK HANDLING
-- ===============================================================================

--- Scroll to a markdown anchor (heading)
-- @param anchor string: Anchor name (without #)
local function scroll_to_anchor(anchor)
    if not state.parsed_ast or not state.parsed_ast.children then
        return
    end

    -- Normalize anchor for comparison
    local target = anchor:lower():gsub("%s+", "-"):gsub("[^%w%-]", "")

    -- Find matching heading
    for _, node in ipairs(state.parsed_ast.children) do
        if node.type == Parser.NodeTypes.HEADING then
            -- Extract heading text
            local heading_text = ""
            if node.children then
                for _, child in ipairs(node.children) do
                    if child.type == Parser.NodeTypes.TEXT then
                        heading_text = heading_text .. (child.text or "")
                    end
                end
            end

            -- Normalize heading text to anchor format
            local heading_anchor = heading_text:lower():gsub("%s+", "-"):gsub("[^%w%-]", "")

            if heading_anchor == target then
                state.scroll_to_line = node.line_start
                return
            end
        end
    end

    show_status("Anchor not found: #" .. anchor)
end

--- Parse a time spec string into seconds.
-- Accepts:
--   HH:MM:SS(.ms), MM:SS(.ms), SS(.ms)
-- Examples: "1:23:45", "2:30", "12.5", "90"
-- @param s string: Time spec
-- @return number|nil: Seconds, or nil if unparseable
local function parse_time_spec(s)
    if not s or s == "" then return nil end
    -- HH:MM:SS(.ms)
    local h, m, sec = s:match("^(%d+):(%d+):([%d%.]+)$")
    if h then
        local sn = tonumber(sec)
        if sn then return tonumber(h) * 3600 + tonumber(m) * 60 + sn end
    end
    -- MM:SS(.ms)
    local m2, s2 = s:match("^(%d+):([%d%.]+)$")
    if m2 then
        local sn = tonumber(s2)
        if sn then return tonumber(m2) * 60 + sn end
    end
    -- Plain seconds (int or float)
    local n = tonumber(s)
    return n
end

--- Format seconds as MM:SS (or HH:MM:SS if >= 1 hour) for status display.
local function format_time_pretty(seconds)
    if not seconds then return "?" end
    local total = math.floor(seconds + 0.5)
    local h = math.floor(total / 3600)
    local m = math.floor((total % 3600) / 60)
    local s = total % 60
    if h > 0 then
        return string.format("%d:%02d:%02d", h, m, s)
    end
    return string.format("%d:%02d", m, s)
end

--- Handle a clicked link
-- @param url string: URL that was clicked
local function handle_link_click(url)
    if not url then
        return
    end

    if url:match("^#") then
        -- Internal anchor - scroll to heading
        local anchor = url:sub(2)
        scroll_to_anchor(anchor)

    elseif url:match("^time://") then
        -- Custom scheme: jump REAPER edit cursor to a timestamp
        local spec = url:sub(8)  -- strip "time://"
        local seconds = parse_time_spec(spec)
        if seconds then
            reaper.SetEditCurPos(seconds, true, false)  -- moveview=true, seekplay=false
            show_status("Jumped to " .. format_time_pretty(seconds))
        else
            show_status("Invalid time link: " .. url)
        end

    elseif url:match("^https?://") then
        -- External URL
        if reaper.CF_ShellExecute then
            reaper.CF_ShellExecute(url)
        else
            -- Fallback: copy to clipboard
            if reaper.CF_SetClipboard then
                reaper.CF_SetClipboard(url)
                reaper.MB("Link copied to clipboard:\n" .. url, "ReaMD", 0)
            else
                reaper.MB("Cannot open link (install SWS extension):\n" .. url, "ReaMD", 0)
            end
        end

    elseif url:match("%.md$") or url:match("%.markdown$") then
        -- Relative markdown file
        if state.file_path then
            local dir = Utils.get_directory(state.file_path)
            local full_path = Utils.join_path(dir, url)
            load_markdown_file(full_path)
        else
            show_status("No current file - cannot resolve relative path")
        end
    else
        -- Unknown link type - try to open it
        if reaper.CF_ShellExecute then
            reaper.CF_ShellExecute(url)
        else
            show_status("Unknown link type: " .. url)
        end
    end
end

-- ===============================================================================
-- SCENARIO MODE
-- ===============================================================================

--- Handle scenario mode updates during playback
-- v2: Supports multiple active fragments (overlapping items)
local function handle_scenario_update()
    if not state.scenario_enabled then
        return
    end

    local changed, fragments, should_scroll = ScenarioEngine.update()

    if #fragments > 0 then
        -- Build set of active line_starts with their highlight colors
        local active_lines = {}
        for _, frag in ipairs(fragments) do
            local cat_info = ScenarioEngine.get_color_category_info(frag.color_category)
            active_lines[frag.line_start] = cat_info.color
        end
        state.highlight_lines = active_lines

        -- Scroll to first fragment if auto_scroll enabled
        if should_scroll then
            state.scroll_to_line = fragments[1].line_start
        end
    elseif changed then
        -- Exited all linked items
        state.highlight_lines = nil
    end
end

--- Auto-link regions to headings by name matching
local function auto_link_regions()
    if not state.parsed_ast then
        show_status("Load a markdown file first")
        return
    end

    local count = ScenarioEngine.auto_link_by_name(state.parsed_ast)

    if count > 0 then
        -- Save the mapping
        if state.file_path and state.content_hash then
            ScenarioEngine.save_mapping(state.file_path, state.content_hash)
        end
        show_status("Linked " .. count .. " region(s) to headings")
    else
        show_status("No matching regions found")
    end
end

--- Toggle scenario mode
local function toggle_scenario_mode()
    state.scenario_enabled = not state.scenario_enabled

    if state.scenario_enabled then
        ScenarioEngine.init()
        ScenarioEngine.refresh_regions()
        if state.file_path then
            ScenarioEngine.load_mapping(state.file_path)
        end
        show_status("Scenario mode enabled")
    else
        state.highlight_lines = nil
        show_status("Scenario mode disabled")
    end
end

-- ===============================================================================
-- UI COMPONENTS
-- ===============================================================================

--- Render the toolbar
local function render_toolbar()
    -- Add top/left padding
    local TOOLBAR_PADDING = 8
    reaper.ImGui_SetCursorPosX(ctx, reaper.ImGui_GetCursorPosX(ctx) + TOOLBAR_PADDING)
    reaper.ImGui_SetCursorPosY(ctx, reaper.ImGui_GetCursorPosY(ctx) + TOOLBAR_PADDING)

    -- ═══════════════════════════════════════════════════════════════════════
    -- LEFT SIDE: File operations
    -- ═══════════════════════════════════════════════════════════════════════

    -- New dropdown menu
    if reaper.ImGui_Button(ctx, "New") then
        reaper.ImGui_OpenPopup(ctx, "new_menu")
    end

    if reaper.ImGui_BeginPopup(ctx, "new_menu") then
        if reaper.ImGui_MenuItem(ctx, "Markdown") then
            -- Create new empty markdown
            state.markdown_content = ""
            state.parsed_ast = nil
            state.file_path = nil
            state.file_name = "Untitled.md"
            state.is_new_file = true
            state.edit_mode = true  -- Start in edit mode
            state.edit_changed = false
            state.scenario_enabled = false
            state.highlight_lines = nil
            -- Auto-focus the editor so the user can start typing immediately
            -- (without this, REAPER captures the keys as global shortcuts)
            state.focus_editor_next_frame = true
            show_status("New markdown - edit and save")
        end

        reaper.ImGui_Separator(ctx)

        if reaper.ImGui_MenuItem(ctx, "AI Parse...") then
            AIParser.show()
        end

        reaper.ImGui_EndPopup(ctx)
    end

    reaper.ImGui_SameLine(ctx)

    -- Open dropdown menu
    if reaper.ImGui_Button(ctx, "Open...") then
        reaper.ImGui_OpenPopup(ctx, "open_menu")
    end

    if reaper.ImGui_BeginPopup(ctx, "open_menu") then
        if reaper.ImGui_MenuItem(ctx, "Browse...") then
            open_file_dialog()
        end

        -- Recent files (filter out non-existent files)
        local recent = Config.get_recent_files()
        local valid_recent = {}
        for _, path in ipairs(recent) do
            local f = io.open(path, "r")
            if f then
                f:close()
                table.insert(valid_recent, path)
            else
                -- Remove non-existent file from list
                Config.remove_recent_file(path)
            end
        end

        if #valid_recent > 0 then
            reaper.ImGui_Separator(ctx)
            reaper.ImGui_TextDisabled(ctx, "Recent:")

            for _, path in ipairs(valid_recent) do
                -- Show only filename, use full path as unique ID
                local name = path:match("([^/\\]+)$") or path
                if reaper.ImGui_MenuItem(ctx, name .. "##" .. path) then
                    load_markdown_file(path)
                end
            end
        end

        reaper.ImGui_EndPopup(ctx)
    end

    reaper.ImGui_SameLine(ctx)

    -- Edit Mode toggle
    local edit_active = state.edit_mode
    local edit_label = edit_active and "Edit: ON" or "Edit"
    if edit_active then
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0xCC9933FF)
    end
    if reaper.ImGui_Button(ctx, edit_label) then
        local was_editing = state.edit_mode
        state.edit_mode = not state.edit_mode
        if state.edit_mode then
            state.focus_editor_next_frame = true  -- auto-focus the InputText
            show_status("Edit mode: modify text, click Save")
        else
            -- Exiting edit mode: re-parse if content was changed
            if was_editing and state.edit_changed and state.markdown_content then
                state.parsed_ast = Parser.parse(state.markdown_content)
            end
        end
    end
    if edit_active then
        reaper.ImGui_PopStyleColor(ctx)
    end

    -- Save button (only in edit mode with unsaved changes)
    if state.edit_mode and state.edit_changed then
        reaper.ImGui_SameLine(ctx)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0x33CC33FF)
        if reaper.ImGui_Button(ctx, "Save") then
            save_markdown_file()
        end
        reaper.ImGui_PopStyleColor(ctx)
        if reaper.ImGui_IsItemHovered(ctx) then
            reaper.ImGui_SetTooltip(ctx, "Save changes to disk (Ctrl+S)")
        end
    end

    -- "AI Parse" shortcut: when in edit mode, lets the user format the current
    -- editor contents without copy-pasting into the AI Parse window.
    if state.edit_mode and state.markdown_content and state.markdown_content ~= "" then
        reaper.ImGui_SameLine(ctx)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0x0E639CFF)
        if reaper.ImGui_Button(ctx, "AI Parse") then
            AIParser.state.input_text = state.markdown_content
            AIParser.state.result_markdown = nil
            AIParser.state.error_message = nil
            AIParser.state.show_window = true
        end
        reaper.ImGui_PopStyleColor(ctx)
        if reaper.ImGui_IsItemHovered(ctx) then
            reaper.ImGui_SetTooltip(ctx,
                "Send current editor content to Claude for formatting.\n" ..
                "Result can be applied to the editor or saved as a new file.")
        end
    end

    -- Live Preview toggle (only visible in edit mode)
    if state.edit_mode then
        reaper.ImGui_SameLine(ctx)
        local live_preview = Config.get("live_preview")
        local preview_label = live_preview and "Preview: ON" or "Preview"
        if live_preview then
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0x9966CCFF)
        end
        if reaper.ImGui_Button(ctx, preview_label) then
            Config.set("live_preview", not live_preview)
            Config.save()
        end
        if live_preview then
            reaper.ImGui_PopStyleColor(ctx)
        end
    end

    reaper.ImGui_SameLine(ctx)
    reaper.ImGui_Text(ctx, " | ")
    reaper.ImGui_SameLine(ctx)

    -- ═══════════════════════════════════════════════════════════════════════
    -- MIDDLE: Scenario controls
    -- ═══════════════════════════════════════════════════════════════════════

    -- Scenario toggle
    local scenario_active = state.scenario_enabled
    local scenario_label = scenario_active and "Scenario: ON" or "Scenario"
    if scenario_active then
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0x336699FF)
    end
    if reaper.ImGui_Button(ctx, scenario_label) then
        toggle_scenario_mode()
    end
    if scenario_active then
        reaper.ImGui_PopStyleColor(ctx)
    end

    -- Scenario mode buttons
    if state.scenario_enabled then
        reaper.ImGui_SameLine(ctx)

        -- Save Scenario button
        if reaper.ImGui_Button(ctx, "Save Map") then
            if state.file_path then
                if ScenarioEngine.save_to_file(state.file_path) then
                    show_status("Scenario saved")
                else
                    show_status("Failed to save")
                end
            else
                show_status("No file loaded")
            end
        end
        if reaper.ImGui_IsItemHovered(ctx) then
            reaper.ImGui_SetTooltip(ctx, "Save the fragment-to-item map to <file>.md.reamd")
        end

        reaper.ImGui_SameLine(ctx)

        -- Scenario Tools menu (Auto-Link, Export to Regions)
        if reaper.ImGui_Button(ctx, "Tools") then
            reaper.ImGui_OpenPopup(ctx, "scenario_tools_menu")
        end
        if reaper.ImGui_BeginPopup(ctx, "scenario_tools_menu") then
            if reaper.ImGui_MenuItem(ctx, "Auto-Link by name") then
                if state.parsed_ast then
                    local items_n = ScenarioEngine.auto_link_by_item_name(state.parsed_ast)
                    local regions_n = ScenarioEngine.auto_link_by_name(state.parsed_ast)
                    local total = items_n + regions_n
                    if total > 0 and state.file_path and state.content_hash then
                        ScenarioEngine.save_mapping(state.file_path, state.content_hash)
                    end
                    if total > 0 then
                        show_status(string.format(
                            "Linked %d (%d items, %d regions)",
                            total, items_n, regions_n))
                    else
                        show_status("No matches found (check heading/row text vs take/region names)")
                    end
                else
                    show_status("Load a markdown file first")
                end
            end
            if reaper.ImGui_IsItemHovered(ctx) then
                reaper.ImGui_SetTooltip(ctx,
                    "Match heading/row text against take names AND region names.\n" ..
                    "Skips lines that already have links.")
            end

            if reaper.ImGui_MenuItem(ctx, "Export linked fragments to regions") then
                local n = ScenarioEngine.export_to_regions()
                if n > 0 then
                    show_status("Created " .. n .. " region(s)")
                else
                    show_status("Nothing to export (no fragments with resolvable items)")
                end
            end
            if reaper.ImGui_IsItemHovered(ctx) then
                reaper.ImGui_SetTooltip(ctx,
                    "Creates a REAPER region per linked fragment, named with the fragment's identifier and colored by category.")
            end

            reaper.ImGui_EndPopup(ctx)
        end

        reaper.ImGui_SameLine(ctx)

        -- Cue List toggle
        local cue_active = CueList.is_visible()
        local cue_label = cue_active and "Cue: ON" or "Cue"
        if cue_active then
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0x66AA66FF)
        end
        if reaper.ImGui_Button(ctx, cue_label) then
            CueList.toggle()
            Config.set("cue_list_visible", CueList.is_visible())
            Config.save()
        end
        if cue_active then reaper.ImGui_PopStyleColor(ctx) end
        if reaper.ImGui_IsItemHovered(ctx) then
            reaper.ImGui_SetTooltip(ctx, "Sortable cue list of all linked fragments")
        end

        reaper.ImGui_SameLine(ctx)

        -- Teleprompter toggle
        local tp_active = Teleprompter.is_enabled()
        local tp_label = tp_active and "Prompt: ON" or "Prompt"
        if tp_active then
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0x3399CCFF)
        end
        if reaper.ImGui_Button(ctx, tp_label) then
            Teleprompter.toggle()
        end
        if tp_active then
            reaper.ImGui_PopStyleColor(ctx)
        end
        if reaper.ImGui_IsItemHovered(ctx) then
            reaper.ImGui_SetTooltip(ctx, "Toggle teleprompter overlay")
        end
    end

    -- ═══════════════════════════════════════════════════════════════════════
    -- RIGHT SIDE: Settings
    -- ═══════════════════════════════════════════════════════════════════════

    reaper.ImGui_SameLine(ctx)
    reaper.ImGui_Text(ctx, " | ")
    reaper.ImGui_SameLine(ctx)

    if reaper.ImGui_Button(ctx, "Settings") then
        state.show_settings = not state.show_settings
    end

    -- ═══════════════════════════════════════════════════════════════════════
    -- SECOND ROW: File info and status
    -- ═══════════════════════════════════════════════════════════════════════

    -- New line for file info
    reaper.ImGui_SetCursorPosX(ctx, TOOLBAR_PADDING)

    -- File name (with unsaved-changes asterisk and hover-for-full-path)
    if state.file_name then
        local star = (state.edit_mode and state.edit_changed) and "*" or ""
        reaper.ImGui_TextDisabled(ctx, star .. state.file_name)
        if state.file_path and reaper.ImGui_IsItemHovered(ctx) then
            reaper.ImGui_SetTooltip(ctx, state.file_path)
        end
        if state.status_message then
            reaper.ImGui_SameLine(ctx)
        end
    end

    -- Status message
    if state.status_message then
        reaper.ImGui_TextColored(ctx, 0x88CC88FF, " - " .. state.status_message)
    end

    reaper.ImGui_Separator(ctx)
end

--- Render the in-document search bar (visible after Ctrl+F).
local function render_search_bar()
    if not state.search_visible then return end

    local PAD = 8
    reaper.ImGui_SetCursorPosX(ctx, reaper.ImGui_GetCursorPosX(ctx) + PAD)

    reaper.ImGui_Text(ctx, "Find:")
    reaper.ImGui_SameLine(ctx)

    reaper.ImGui_SetNextItemWidth(ctx, 260)
    if state.search_focus_next_frame then
        reaper.ImGui_SetKeyboardFocusHere(ctx)
        state.search_focus_next_frame = false
    end

    local flags = reaper.ImGui_InputTextFlags_EnterReturnsTrue()
    local prev_q = state.search_query or ""
    local enter_pressed, new_q = reaper.ImGui_InputText(ctx, "##search_q", prev_q, flags)

    -- Detect text change by comparing (EnterReturnsTrue only fires on Enter,
    -- not on every keystroke, so we need this manual diff).
    if new_q ~= prev_q then
        state.search_query = new_q
        rebuild_search_matches()
    end

    if enter_pressed then
        search_next()
        state.search_focus_next_frame = true  -- re-focus input
    end

    -- Match counter / status
    reaper.ImGui_SameLine(ctx)
    local total = state.search_matches and #state.search_matches or 0
    if total > 0 then
        reaper.ImGui_TextDisabled(ctx, string.format("%d / %d", state.search_idx, total))
    elseif state.search_query and state.search_query ~= "" then
        reaper.ImGui_TextColored(ctx, 0xCC6666FF, "no matches")
    else
        reaper.ImGui_TextDisabled(ctx, "  ")
    end

    -- Prev / Next / Close
    reaper.ImGui_SameLine(ctx)
    if reaper.ImGui_SmallButton(ctx, "<##sp") then search_prev() end
    if reaper.ImGui_IsItemHovered(ctx) then
        reaper.ImGui_SetTooltip(ctx, "Previous match (Shift+F3)")
    end
    reaper.ImGui_SameLine(ctx, 0, 2)
    if reaper.ImGui_SmallButton(ctx, ">##sn") then search_next() end
    if reaper.ImGui_IsItemHovered(ctx) then
        reaper.ImGui_SetTooltip(ctx, "Next match (Enter / F3)")
    end

    reaper.ImGui_SameLine(ctx, 0, 8)
    if reaper.ImGui_SmallButton(ctx, "X##sc") then search_close() end
    if reaper.ImGui_IsItemHovered(ctx) then
        reaper.ImGui_SetTooltip(ctx, "Close search (Esc)")
    end

    reaper.ImGui_Separator(ctx)
end

--- Render the main content area with markdown
local function render_content()
    -- Get available size for content
    local avail_w, avail_h = reaper.ImGui_GetContentRegionAvail(ctx)

    -- Create scrollable child window for content
    -- v0.10 API: BeginChild(ctx, id, w, h, child_flags, window_flags)
    local child_flags = reaper.ImGui_ChildFlags_None and reaper.ImGui_ChildFlags_None() or 0
    local window_flags = reaper.ImGui_WindowFlags_HorizontalScrollbar()

    if reaper.ImGui_BeginChild(ctx, "markdown_content", avail_w, avail_h, child_flags, window_flags) then
        -- Add padding/margins
        local CONTENT_PADDING = 12
        reaper.ImGui_SetCursorPosX(ctx, reaper.ImGui_GetCursorPosX(ctx) + CONTENT_PADDING)
        reaper.ImGui_SetCursorPosY(ctx, reaper.ImGui_GetCursorPosY(ctx) + CONTENT_PADDING)

        -- Indent all content for right margin effect
        reaper.ImGui_PushTextWrapPos(ctx, avail_w - CONTENT_PADDING * 2)

        if fonts.normal then
            reaper.ImGui_PushFont(ctx, fonts.normal, fonts.sizes.normal)
        end

        -- EDIT MODE: Show raw markdown in editable text field
        if state.edit_mode and state.markdown_content ~= nil then
            local live_preview = Config.get("live_preview")
            local text_h = avail_h - CONTENT_PADDING * 2 - 10  -- Leave some margin
            local input_flags = reaper.ImGui_InputTextFlags_AllowTabInput()

            if live_preview then
                -- ═══════════════════════════════════════════════════════════════
                -- SPLIT VIEW: Editor (left) + Live Preview (right)
                -- ═══════════════════════════════════════════════════════════════
                local table_flags = reaper.ImGui_TableFlags_Resizable()
                                  + reaper.ImGui_TableFlags_BordersInnerV()

                if reaper.ImGui_BeginTable(ctx, "edit_split", 2, table_flags) then
                    -- Setup columns with equal initial width
                    local col_width = (avail_w - CONTENT_PADDING * 2) / 2
                    reaper.ImGui_TableSetupColumn(ctx, "editor", reaper.ImGui_TableColumnFlags_WidthStretch(), col_width)
                    reaper.ImGui_TableSetupColumn(ctx, "preview", reaper.ImGui_TableColumnFlags_WidthStretch(), col_width)

                    reaper.ImGui_TableNextRow(ctx)

                    -- LEFT COLUMN: Editor
                    reaper.ImGui_TableSetColumnIndex(ctx, 0)

                    if fonts.code then
                        reaper.ImGui_PushFont(ctx, fonts.code, fonts.sizes.code)
                    end

                    local editor_w = reaper.ImGui_GetContentRegionAvail(ctx)
                    -- Auto-focus when entering edit mode (after New > Markdown
                    -- or "New Markdown" welcome button). Without this, REAPER
                    -- captures keystrokes as global action shortcuts.
                    if state.focus_editor_next_frame then
                        reaper.ImGui_SetKeyboardFocusHere(ctx)
                        state.focus_editor_next_frame = false
                    end
                    local changed, new_text = reaper.ImGui_InputTextMultiline(
                        ctx,
                        "##edit_text",
                        state.markdown_content,
                        editor_w,
                        text_h,
                        input_flags
                    )

                    -- Track changes and re-parse for live preview
                    if changed then
                        state.markdown_content = new_text
                        state.edit_changed = true
                        -- Re-parse for live preview
                        state.parsed_ast = Parser.parse(new_text)
                    end

                    if fonts.code then
                        reaper.ImGui_PopFont(ctx)
                    end

                    -- RIGHT COLUMN: Live Preview
                    reaper.ImGui_TableSetColumnIndex(ctx, 1)

                    -- Render preview in a child window for scrolling
                    local preview_w = reaper.ImGui_GetContentRegionAvail(ctx)
                    local child_flags = reaper.ImGui_ChildFlags_None and reaper.ImGui_ChildFlags_None() or 0
                    local window_flags = reaper.ImGui_WindowFlags_None()

                    if reaper.ImGui_BeginChild(ctx, "##live_preview", preview_w, text_h, child_flags, window_flags) then
                        if state.parsed_ast then
                            local render_state = {
                                scroll_y = 0,
                                scroll_to_line = nil,
                                highlight_lines = nil,
                                clicked_link = nil,
                                scenario_enabled = false,  -- Disable scenario in preview
                                scenario_engine = nil,
                                scenario_changed = false,
                            }
                            Renderer.render(ctx, state.parsed_ast, fonts, render_state)
                        end
                        reaper.ImGui_EndChild(ctx)
                    end

                    reaper.ImGui_EndTable(ctx)
                end
            else
                -- ═══════════════════════════════════════════════════════════════
                -- EDITOR ONLY (no live preview)
                -- ═══════════════════════════════════════════════════════════════
                if fonts.code then
                    reaper.ImGui_PushFont(ctx, fonts.code, fonts.sizes.code)
                end

                if state.focus_editor_next_frame then
                    reaper.ImGui_SetKeyboardFocusHere(ctx)
                    state.focus_editor_next_frame = false
                end
                local changed, new_text = reaper.ImGui_InputTextMultiline(
                    ctx,
                    "##edit_text",
                    state.markdown_content,
                    avail_w - CONTENT_PADDING * 2,
                    text_h,
                    input_flags
                )

                if changed then
                    state.markdown_content = new_text
                    state.edit_changed = true
                end

                if fonts.code then
                    reaper.ImGui_PopFont(ctx)
                end
            end

        elseif state.parsed_ast then
            -- NORMAL MODE: Render formatted markdown

            -- Merge scenario highlights with search highlights for this frame.
            -- Search matches use a distinct color (yellow/orange) so they don't
            -- visually clash with category colors when both apply.
            local merged_highlights = nil
            if state.highlight_lines or (state.search_matches and #state.search_matches > 0) then
                merged_highlights = {}
                if state.highlight_lines then
                    for k, v in pairs(state.highlight_lines) do
                        merged_highlights[k] = v
                    end
                end
                if state.search_matches then
                    for i, line in ipairs(state.search_matches) do
                        if not merged_highlights[line] then
                            -- Current match: orange. Other matches: pale yellow.
                            merged_highlights[line] = (i == state.search_idx)
                                and 0xFF990088 or 0xFFEE0044
                        end
                    end
                end
            end

            -- Create render state
            local render_state = {
                scroll_y = state.scroll_y,
                scroll_to_line = state.scroll_to_line,
                highlight_lines = merged_highlights,
                clicked_link = nil,
                -- Scenario mode state
                scenario_enabled = state.scenario_enabled,
                scenario_engine = ScenarioEngine,
                scenario_changed = false,
            }

            -- Render markdown
            Renderer.render(ctx, state.parsed_ast, fonts, render_state)

            -- Handle scroll-to-line (may need multiple frames)
            if render_state.scroll_to_line then
                -- Request was not fully processed, keep it for next frame
                state.scroll_to_line = render_state.scroll_to_line
            else
                state.scroll_to_line = nil
            end

            -- Update scroll position
            state.scroll_y = render_state.scroll_y

            -- Handle link click
            if render_state.clicked_link then
                state.clicked_link = render_state.clicked_link
            end

            -- Auto-persist scenario edits: project ExtState (session) + .reamd
            -- sidecar file (portable). save_to_file is a no-op when there are
            -- no fragments, so this is cheap.
            if render_state.scenario_changed and state.file_path and state.content_hash then
                ScenarioEngine.save_mapping(state.file_path, state.content_hash)
                ScenarioEngine.save_to_file(state.file_path)
            end
        else
            -- ────────────────────────────────────────────────────────────
            -- Welcome screen (no file loaded)
            -- ────────────────────────────────────────────────────────────
            if fonts.h2 then
                reaper.ImGui_PushFont(ctx, fonts.h2, fonts.sizes.h2 or 20)
            end
            reaper.ImGui_TextColored(ctx, 0x3366CCFF, "ReaMD")
            if fonts.h2 then reaper.ImGui_PopFont(ctx) end

            reaper.ImGui_TextDisabled(ctx, "Markdown viewer for REAPER — for VO, post-prod, podcasts.")
            reaper.ImGui_Spacing(ctx); reaper.ImGui_Separator(ctx); reaper.ImGui_Spacing(ctx)

            -- Quick actions row
            if reaper.ImGui_Button(ctx, "Open File...##welcome", 140, 30) then
                open_file_dialog()
            end
            reaper.ImGui_SameLine(ctx)
            if reaper.ImGui_Button(ctx, "New Markdown##welcome", 140, 30) then
                state.markdown_content = ""
                state.parsed_ast = nil
                state.file_path = nil
                state.file_name = "Untitled.md"
                state.is_new_file = true
                state.edit_mode = true
                state.edit_changed = false
                state.scenario_enabled = false
                state.highlight_lines = nil
                state.focus_editor_next_frame = true
                show_status("New markdown - edit and save")
            end
            reaper.ImGui_SameLine(ctx)
            if reaper.ImGui_Button(ctx, "AI Parse...##welcome", 140, 30) then
                AIParser.show()
            end

            reaper.ImGui_Spacing(ctx)

            -- Recent files (top 5)
            local recent = Config.get_recent_files()
            local shown_recent = 0
            for _, path in ipairs(recent) do
                if shown_recent >= 5 then break end
                local f = io.open(path, "r")
                if f then
                    f:close()
                    shown_recent = shown_recent + 1
                    if shown_recent == 1 then
                        reaper.ImGui_TextDisabled(ctx, "Recent files:")
                    end
                    local name = path:match("([^/\\]+)$") or path
                    if reaper.ImGui_Selectable(ctx, "  " .. name .. "##recent" .. path, false) then
                        load_markdown_file(path)
                    end
                    if reaper.ImGui_IsItemHovered(ctx) then
                        reaper.ImGui_SetTooltip(ctx, path)
                    end
                end
            end

            reaper.ImGui_Spacing(ctx); reaper.ImGui_Separator(ctx); reaper.ImGui_Spacing(ctx)
            reaper.ImGui_TextDisabled(ctx, "Features:")
            reaper.ImGui_BulletText(ctx, "Full markdown rendering (headers, lists, tables, code, strikethrough)")
            reaper.ImGui_BulletText(ctx, "Scenario Mode — link headings/rows to timeline items")
            reaper.ImGui_BulletText(ctx, "Teleprompter — auto-scrolling VO display")
            reaper.ImGui_BulletText(ctx, "AI Parse — format messy text with Claude")
            reaper.ImGui_BulletText(ctx, "time:// links jump REAPER edit cursor")
            reaper.ImGui_BulletText(ctx, "Search (Ctrl+F), keyboard shortcuts (Ctrl+S/O/E)")
        end

        if fonts.normal then
            reaper.ImGui_PopFont(ctx)
        end

        -- Pop text wrap position
        reaper.ImGui_PopTextWrapPos(ctx)

        reaper.ImGui_EndChild(ctx)
    end
end

--- Render the settings panel as a modal
local function render_settings_panel()
    -- Center the modal
    local viewport_w, viewport_h = reaper.ImGui_GetWindowSize(ctx)
    reaper.ImGui_SetNextWindowPos(ctx, viewport_w / 2, viewport_h / 2,
        reaper.ImGui_Cond_Appearing(), 0.5, 0.5)
    reaper.ImGui_SetNextWindowSize(ctx, 350, 300, reaper.ImGui_Cond_Appearing())

    local popup_flags = reaper.ImGui_WindowFlags_NoCollapse()
    local visible, open = reaper.ImGui_Begin(ctx, "ReaMD Settings", true, popup_flags)

    if visible then
        -- Theme dropdown
        local themes = {"light", "dark", "auto"}
        local current_theme = Config.get("theme")
        local current_idx = 1
        for i, t in ipairs(themes) do
            if t == current_theme then
                current_idx = i
                break
            end
        end

        if reaper.ImGui_BeginCombo(ctx, "Theme", themes[current_idx]) then
            for i, theme in ipairs(themes) do
                local is_selected = (current_idx == i)
                if reaper.ImGui_Selectable(ctx, theme, is_selected) then
                    Config.set("theme", theme)
                end
                if is_selected then
                    reaper.ImGui_SetItemDefaultFocus(ctx)
                end
            end
            reaper.ImGui_EndCombo(ctx)
        end

        -- Font size slider (applies to next frame; fonts rebuild via setup_fonts
        -- on save/close)
        local cur_size = Config.get("font_size") or 14
        local font_changed, new_size = reaper.ImGui_SliderInt(ctx, "Font size", cur_size, 10, 24)
        if font_changed then
            Config.set("font_size", new_size)
        end
        if reaper.ImGui_IsItemHovered(ctx) then
            reaper.ImGui_SetTooltip(ctx, "Base font size. Headings scale relative to this.\nReopen the script (or reload fonts) to apply.")
        end

        reaper.ImGui_Spacing(ctx)
        reaper.ImGui_Separator(ctx)
        reaper.ImGui_Spacing(ctx)

        reaper.ImGui_Text(ctx, "Scenario Mode Settings")
        reaper.ImGui_Spacing(ctx)

        -- Auto-scroll checkbox
        local auto_scroll = Config.get("auto_scroll")
        local changed_auto, new_auto = reaper.ImGui_Checkbox(ctx, "Auto-scroll during playback", auto_scroll)
        if changed_auto then
            Config.set("auto_scroll", new_auto)
        end

        -- Scroll offset slider (0.0-1.0)
        local scroll_offset = Config.get("scroll_offset")
        local changed_offset, new_offset = reaper.ImGui_SliderDouble(ctx, "Scroll Offset", scroll_offset, 0.0, 1.0, "%.2f")
        if changed_offset then
            Config.set("scroll_offset", new_offset)
        end
        reaper.ImGui_SameLine(ctx)
        if reaper.ImGui_IsItemHovered(ctx) then
            reaper.ImGui_SetTooltip(ctx, "Position of highlighted text in viewport (0=top, 1=bottom)")
        end

        -- Scroll speed slider (0.5-3.0)
        local scroll_speed = Config.get("scroll_speed")
        local changed_speed, new_speed = reaper.ImGui_SliderDouble(ctx, "Scroll Speed", scroll_speed, 0.5, 3.0, "%.1f")
        if changed_speed then
            Config.set("scroll_speed", new_speed)
        end

        reaper.ImGui_Spacing(ctx)
        reaper.ImGui_Separator(ctx)
        reaper.ImGui_Spacing(ctx)

        reaper.ImGui_Text(ctx, "AI Parser Settings")
        reaper.ImGui_Spacing(ctx)

        -- API Key field (masked)
        local api_key = Config.get("ai_api_key") or ""
        local show_key = state.show_api_key

        reaper.ImGui_SetNextItemWidth(ctx, 180)
        if show_key then
            -- Show actual key (editable)
            local key_changed, new_key = reaper.ImGui_InputText(ctx, "API Key", api_key)
            if key_changed then
                Config.set("ai_api_key", new_key)
            end
        else
            -- Show masked key (read-only display)
            local masked = api_key ~= "" and string.rep("*", math.min(#api_key, 24)) or "(not set)"
            reaper.ImGui_InputText(ctx, "API Key", masked, reaper.ImGui_InputTextFlags_ReadOnly())
        end

        reaper.ImGui_SameLine(ctx)
        if reaper.ImGui_Button(ctx, show_key and "Hide" or "Show") then
            state.show_api_key = not state.show_api_key
        end

        -- Model selector
        local MODELS = {
            {id = "claude-haiku-4-5-20251001",  label = "Haiku 4.5  (fast, cheap)"},
            {id = "claude-sonnet-4-6",          label = "Sonnet 4.6 (balanced)"},
            {id = "claude-opus-4-7",            label = "Opus 4.7   (highest quality)"},
        }
        local current_model = Config.get("ai_model") or MODELS[1].id
        local current_label = MODELS[1].label
        for _, m in ipairs(MODELS) do
            if m.id == current_model then current_label = m.label; break end
        end

        reaper.ImGui_SetNextItemWidth(ctx, 220)
        if reaper.ImGui_BeginCombo(ctx, "Model", current_label) then
            for _, m in ipairs(MODELS) do
                local is_selected = (m.id == current_model)
                if reaper.ImGui_Selectable(ctx, m.label, is_selected) then
                    Config.set("ai_model", m.id)
                end
                if is_selected then reaper.ImGui_SetItemDefaultFocus(ctx) end
            end
            reaper.ImGui_EndCombo(ctx)
        end
        if reaper.ImGui_IsItemHovered(ctx) then
            reaper.ImGui_SetTooltip(ctx,
                "Haiku = cheapest, ~2-5s\nSonnet = balanced quality\nOpus = best for tricky structure")
        end

        -- Edit Prompt button
        if reaper.ImGui_Button(ctx, "Edit Prompt") then
            AIParser.open_prompt_editor()
        end
        if reaper.ImGui_IsItemHovered(ctx) then
            reaper.ImGui_SetTooltip(ctx, "Opens prompt file in your default text editor")
        end

        reaper.ImGui_Spacing(ctx)
        reaper.ImGui_Separator(ctx)
        reaper.ImGui_Spacing(ctx)

        -- Save button
        if reaper.ImGui_Button(ctx, "Save Settings") then
            Config.save()
            show_status("Settings saved")
        end

        reaper.ImGui_SameLine(ctx)

        -- Reset button
        if reaper.ImGui_Button(ctx, "Reset to Defaults") then
            Config.reset()
            show_status("Settings reset to defaults")
        end

        reaper.ImGui_SameLine(ctx)

        -- Close button
        if reaper.ImGui_Button(ctx, "Close") then
            Config.save()
            state.show_settings = false
        end

        reaper.ImGui_End(ctx)
    end

    if not open then
        Config.save()
        state.show_settings = false
    end
end

--- Render the AI Parse floating window
local function render_ai_parse_window()
    if not AIParser.is_visible() then
        return
    end

    -- Poll for async response
    if AIParser.state.is_loading then
        AIParser.poll_response()
    end

    -- Window setup - center on screen
    reaper.ImGui_SetNextWindowPos(ctx, 400, 300, reaper.ImGui_Cond_FirstUseEver())
    reaper.ImGui_SetNextWindowSize(ctx, 500, 400, reaper.ImGui_Cond_FirstUseEver())

    local window_flags = reaper.ImGui_WindowFlags_NoCollapse()
    local visible, open = reaper.ImGui_Begin(ctx, "AI Parse - Format Text with AI", true, window_flags)

    if visible then
        local avail_w, avail_h = reaper.ImGui_GetContentRegionAvail(ctx)

        -- Instructions
        reaper.ImGui_TextWrapped(ctx, "Paste unformatted text below. AI will convert it to clean markdown.")
        reaper.ImGui_Spacing(ctx)

        -- Input text area (takes most of the space)
        local text_height = avail_h - 100  -- Reserve space for buttons

        if AIParser.state.is_loading then
            -- Loading indicator (read-only)
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBg(), 0x2A2A2AFF)
            local elapsed = math.floor(reaper.time_precise() - AIParser.state.start_time)
            reaper.ImGui_InputTextMultiline(ctx, "##ai_input",
                "Processing... (" .. elapsed .. "s)\n\nPlease wait...",
                avail_w, text_height,
                reaper.ImGui_InputTextFlags_ReadOnly())
            reaper.ImGui_PopStyleColor(ctx)
        elseif AIParser.state.result_markdown then
            -- Show the AI-formatted result so the user can review before saving.
            -- Read-only multiline preserves formatting and lets user select/copy.
            reaper.ImGui_TextDisabled(ctx, "Result preview (editable before save):")
            local res_changed, new_result = reaper.ImGui_InputTextMultiline(ctx, "##ai_result",
                AIParser.state.result_markdown,
                avail_w, text_height - 18,
                reaper.ImGui_InputTextFlags_AllowTabInput())
            if res_changed then
                AIParser.state.result_markdown = new_result
            end
        else
            -- Editable input for the source text
            local changed, new_text = reaper.ImGui_InputTextMultiline(ctx, "##ai_input",
                AIParser.state.input_text,
                avail_w, text_height,
                reaper.ImGui_InputTextFlags_AllowTabInput())
            if changed then
                AIParser.state.input_text = new_text
            end
        end

        reaper.ImGui_Spacing(ctx)

        -- Error message
        if AIParser.state.error_message then
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), 0xFF4444FF)
            reaper.ImGui_TextWrapped(ctx, "Error: " .. AIParser.state.error_message)
            reaper.ImGui_PopStyleColor(ctx)
            reaper.ImGui_Spacing(ctx)
        end

        -- Buttons row
        local has_input = AIParser.state.input_text and #AIParser.state.input_text > 0

        if AIParser.state.is_loading then
            -- Cancel button during loading
            if reaper.ImGui_Button(ctx, "Cancel") then
                AIParser.cancel()
            end

            -- Loading animation (animated dots)
            reaper.ImGui_SameLine(ctx)
            local dots = string.rep(".", math.floor(reaper.time_precise() * 2) % 4)
            reaper.ImGui_Text(ctx, "Processing" .. dots)

        elseif AIParser.state.result_markdown then
            -- Result available — show "Apply to Editor" if we came from edit mode
            if state.edit_mode then
                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0xCC9933FF)
                if reaper.ImGui_Button(ctx, "Apply to Editor") then
                    state.markdown_content = AIParser.state.result_markdown
                    state.edit_changed = true
                    state.parsed_ast = Parser.parse(state.markdown_content)
                    AIParser.hide()
                    show_status("AI-formatted text applied to editor")
                end
                reaper.ImGui_PopStyleColor(ctx)
                if reaper.ImGui_IsItemHovered(ctx) then
                    reaper.ImGui_SetTooltip(ctx,
                        "Replace the current editor contents with the formatted result.\n" ..
                        "Don't forget to Save after.")
                end
                reaper.ImGui_SameLine(ctx)
            end
            -- Result available - show Save button
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0x33CC33FF)
            if reaper.ImGui_Button(ctx, "Save As...") then
                -- Save result as new file - use project folder as default
                local last_dir = Config.get("last_directory")
                if not last_dir or last_dir == "" then
                    local proj_path = reaper.GetProjectPath("")
                    if proj_path and proj_path ~= "" then
                        last_dir = proj_path
                    else
                        last_dir = ""
                    end
                end

                local retval, filename
                if reaper.JS_Dialog_BrowseForSaveFile then
                    retval, filename = reaper.JS_Dialog_BrowseForSaveFile(
                        "Save Formatted Markdown",
                        last_dir,
                        "formatted.md",
                        "Markdown files (*.md)\0*.md\0"
                    )
                else
                    retval, filename = reaper.GetUserFileNameForRead(
                        last_dir,
                        "Save As (select or type filename)",
                        "*.md"
                    )
                end

                if retval and filename and filename ~= "" then
                    if not filename:match("%.md$") then
                        filename = filename .. ".md"
                    end

                    local success, err = Utils.write_file(filename, AIParser.state.result_markdown)
                    if success then
                        -- Load the saved file
                        load_markdown_file(filename)
                        AIParser.hide()
                        show_status("Saved and loaded: " .. Utils.get_filename(filename))
                    else
                        AIParser.state.error_message = "Failed to save: " .. (err or "")
                    end
                end
            end
            reaper.ImGui_PopStyleColor(ctx)

            reaper.ImGui_SameLine(ctx)
            if reaper.ImGui_Button(ctx, "Parse Again") then
                AIParser.state.result_markdown = nil
                AIParser.state.error_message = nil
            end

        else
            -- Parse button
            if not has_input then
                reaper.ImGui_BeginDisabled(ctx)
            end

            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0x0E639CFF)
            if reaper.ImGui_Button(ctx, "Parse with AI") then
                if has_input then
                    AIParser.start_api_call(AIParser.state.input_text)
                end
            end
            reaper.ImGui_PopStyleColor(ctx)

            if not has_input then
                reaper.ImGui_EndDisabled(ctx)
            end
        end

        reaper.ImGui_SameLine(ctx)
        if reaper.ImGui_Button(ctx, "Close") then
            AIParser.hide()
        end

        reaper.ImGui_End(ctx)
    end

    if not open then
        AIParser.hide()
    end
end

-- ===============================================================================
-- KEYBOARD SHORTCUTS
-- ===============================================================================

--- Process global keyboard shortcuts when the main window has focus.
-- Uses IsKeyChordPressed where available (ReaImGui v0.10+), falls back
-- gracefully on older builds.
local function handle_shortcuts()
    if not reaper.ImGui_IsKeyChordPressed
       or not reaper.ImGui_Mod_Ctrl then
        return  -- API too old; skip silently rather than erroring
    end

    local ctrl  = reaper.ImGui_Mod_Ctrl()
    local shift = reaper.ImGui_Mod_Shift()

    -- Ctrl+F: open search
    if reaper.ImGui_IsKeyChordPressed(ctx, ctrl + reaper.ImGui_Key_F()) then
        search_open()
    end

    -- Ctrl+S: save (only meaningful in edit mode with changes — but allow it
    -- anyway and let save_markdown_file no-op if nothing changed).
    if reaper.ImGui_IsKeyChordPressed(ctx, ctrl + reaper.ImGui_Key_S()) then
        if state.markdown_content and state.markdown_content ~= "" then
            save_markdown_file()
        end
    end

    -- Ctrl+O: open file
    if reaper.ImGui_IsKeyChordPressed(ctx, ctrl + reaper.ImGui_Key_O()) then
        open_file_dialog()
    end

    -- Ctrl+E: toggle edit mode
    if reaper.ImGui_IsKeyChordPressed(ctx, ctrl + reaper.ImGui_Key_E()) then
        local was_editing = state.edit_mode
        state.edit_mode = not state.edit_mode
        if state.edit_mode then
            state.focus_editor_next_frame = true
        elseif was_editing and state.edit_changed and state.markdown_content then
            state.parsed_ast = Parser.parse(state.markdown_content)
        end
    end

    -- Search-only shortcuts
    if state.search_visible then
        -- Esc: close
        if reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Escape()) then
            search_close()
        end
        -- F3: next, Shift+F3: prev
        if reaper.ImGui_IsKeyChordPressed(ctx, shift + reaper.ImGui_Key_F3()) then
            search_prev()
            state.search_focus_next_frame = true
        elseif reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_F3()) then
            search_next()
            state.search_focus_next_frame = true
        end
    end
end

-- ===============================================================================
-- MAIN LOOP
-- ===============================================================================

-- Forward declaration for cleanup (defined below main_loop)
local cleanup

--- Main defer loop
local function main_loop()
    -- Apply theme colors at start of frame
    apply_theme(ctx)

    -- Set minimum window size
    reaper.ImGui_SetNextWindowSizeConstraints(ctx, MIN_WINDOW_WIDTH, MIN_WINDOW_HEIGHT,
        math.huge, math.huge)

    -- Window title shows unsaved-changes asterisk and current filename.
    -- The '###reamd_main' suffix is the stable ImGui ID — keeps docking/size
    -- state across title changes.
    local window_title = WINDOW_TITLE
    if state.file_name then
        local star = (state.edit_mode and state.edit_changed) and "*" or ""
        window_title = WINDOW_TITLE .. " - " .. star .. state.file_name
    end
    local imgui_id = window_title .. "###reamd_main"

    local visible, open = reaper.ImGui_Begin(ctx, imgui_id, true, WINDOW_FLAGS)

    if visible then
        -- Handle keyboard shortcuts while the main window has focus
        handle_shortcuts()

        -- Render toolbar
        render_toolbar()

        -- Optional in-document search bar (toggled by Ctrl+F)
        render_search_bar()

        -- Render main content
        render_content()

        reaper.ImGui_End(ctx)
    end

    -- Render settings panel (separate window)
    if state.show_settings then
        render_settings_panel()
    end

    -- Render AI Parse window (separate floating window)
    render_ai_parse_window()

    -- Render Cue List (separate floating window). Visible only when scenario data exists.
    CueList.render(ctx, ScenarioEngine, function(frag)
        if frag and frag.line_start then
            state.scroll_to_line = frag.line_start
        end
    end)

    -- Pop theme colors at end of frame
    pop_theme()

    -- Handle scenario updates
    if state.scenario_enabled then
        handle_scenario_update()

        -- Render teleprompter (if enabled)
        if Teleprompter.is_enabled() and state.markdown_content then
            local fragments = ScenarioEngine.get_active_fragments()
            -- Split markdown into lines for text extraction
            local lines = {}
            for line in state.markdown_content:gmatch("[^\n]*") do
                table.insert(lines, line)
            end
            Teleprompter.render(ctx, fragments, lines, ScenarioEngine)
        end
    end

    -- Handle link clicks (after rendering)
    if state.clicked_link then
        handle_link_click(state.clicked_link)
        state.clicked_link = nil
    end

    -- Update status message expiry
    update_status()

    -- Continue loop if window is open
    if open then
        reaper.defer(main_loop)
    else
        cleanup()
    end
end

-- ===============================================================================
-- INITIALIZATION AND CLEANUP
-- ===============================================================================

--- Initialize the application
-- @return boolean: True if initialization succeeded
local function init()
    -- Create ReaImGui context with docking enabled
    ctx = reaper.ImGui_CreateContext(WINDOW_TITLE, reaper.ImGui_ConfigFlags_DockingEnable())
    if not ctx then
        reaper.MB("Failed to create ImGui context", "ReaMD Error", 0)
        return false
    end

    -- Set window flags
    WINDOW_FLAGS = reaper.ImGui_WindowFlags_None()

    -- Setup fonts
    setup_fonts(ctx)

    -- Load configuration
    Config.load()

    -- Initialize scenario engine
    ScenarioEngine.init()

    -- Initialize teleprompter
    Teleprompter.init(ctx, fonts)

    -- Initialize AI parser
    AIParser.init(Utils, Config, json, project_dir)

    -- Restore Cue List visibility from last session
    if Config.get("cue_list_visible") then
        CueList.show()
    end

    return true
end

--- Cleanup resources
cleanup = function()
    -- Save configuration
    Config.save()

    -- Save scenario mapping if file is loaded
    if state.file_path and state.content_hash then
        ScenarioEngine.save_mapping(state.file_path, state.content_hash)
    end

    -- Context is automatically destroyed when script exits
    ctx = nil
end

-- ===============================================================================
-- ENTRY POINT
-- ===============================================================================

local function main()
    if not init() then
        return
    end

    reaper.defer(main_loop)
end

main()
