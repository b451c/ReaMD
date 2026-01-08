# ReaMD Implementation Plan

> **Dockable Markdown Viewer for Reaper DAW with Timeline Synchronization**

## Overview

ReaMD to dokowalny podgląd Markdown dla Reaper DAW z synchronizacją timeline'u. Projekt wypełnia lukę w ekosystemie Reaper - brak natywnego narzędzia do wyświetlania sformatowanego tekstu zsynchronizowanego z pozycją odtwarzania.

### Główne cele
1. Renderowanie Markdown w dokowalnym oknie ReaImGui
2. Synchronizacja tekstu z regionami timeline'u (Scenario Mode)
3. Pełna kompatybilność cross-platform (Windows, macOS, Linux)
4. Dystrybucja przez ReaPack

### Technologie (zdecydowane)
- **GUI**: ReaImGui (wrapper Dear ImGui dla ReaScript)
- **Parser**: Custom Lua markdown parser (pure Lua, ~400 LOC)
- **Dane**: JSON (rxi/json.lua) + Project ExtState
- **Język**: Lua (ReaScript)

---

## Struktura projektu

```
ReaMD/
├── Main/
│   └── ReaMD.lua                   # Główny entry point (Actions menu)
├── Libs/
│   ├── json.lua                    # rxi/json.lua (bundled, 9KB)
│   ├── md_parser.lua               # Custom markdown parser
│   ├── md_renderer.lua             # ReaImGui rendering logic
│   ├── scenario_engine.lua         # Timeline synchronization
│   ├── config.lua                  # User preferences management
│   └── utils.lua                   # Cross-platform utilities
├── Fonts/
│   └── JetBrainsMono-Regular.ttf   # Bundled monospace font (opcjonalnie)
├── Tests/
│   ├── test_parser.lua             # Parser unit tests
│   ├── test_renderer.lua           # Renderer tests
│   └── test_scenario.lua           # Scenario engine tests
└── README.md
```

---

## PHASE 1: Core Viewer

### 1.1 ReaImGui Window Setup

**Plik**: `Main/ReaMD.lua`

**Zadania**:
1. Utworzenie kontekstu ReaImGui z flagą `DockingEnable`
2. Konfiguracja fontów (normal, h1, h2, h3, code, bold, italic)
3. Implementacja głównej pętli defer
4. Obsługa zamykania okna i cleanup

**Implementacja**:

```lua
-- Pseudokod struktury głównej
local ctx = nil
local fonts = {}
local state = {
    markdown_content = "",
    parsed_ast = {},
    scroll_position = 0,
    file_path = nil
}

function init()
    -- Verify ReaImGui is available
    if not reaper.ImGui_CreateContext then
        reaper.MB("ReaImGui extension required.\n\nInstall via ReaPack:\nExtensions > ReaPack > Browse packages > ReaImGui", "ReaMD Error", 0)
        return false
    end

    ctx = reaper.ImGui_CreateContext('ReaMD',
        reaper.ImGui_ConfigFlags_DockingEnable())

    -- Font setup with bold/italic flags (ReaImGui v0.10+)
    fonts.normal = reaper.ImGui_CreateFont('sans-serif', 14)
    fonts.bold = reaper.ImGui_CreateFont('sans-serif', 14,
        reaper.ImGui_FontFlags_Bold())
    fonts.italic = reaper.ImGui_CreateFont('sans-serif', 14,
        reaper.ImGui_FontFlags_Italic())
    fonts.bold_italic = reaper.ImGui_CreateFont('sans-serif', 14,
        reaper.ImGui_FontFlags_Bold() | reaper.ImGui_FontFlags_Italic())
    fonts.h1 = reaper.ImGui_CreateFont('sans-serif', 24,
        reaper.ImGui_FontFlags_Bold())
    fonts.h2 = reaper.ImGui_CreateFont('sans-serif', 20,
        reaper.ImGui_FontFlags_Bold())
    fonts.h3 = reaper.ImGui_CreateFont('sans-serif', 18,
        reaper.ImGui_FontFlags_Bold())
    fonts.code = reaper.ImGui_CreateFont('monospace', 13)

    -- Attach all fonts to context
    for _, font in pairs(fonts) do
        reaper.ImGui_Attach(ctx, font)
    end

    return true
end

function main_loop()
    local visible, open = reaper.ImGui_Begin(ctx, 'ReaMD', true)

    if visible then
        render_toolbar()
        render_content()
        reaper.ImGui_End(ctx)
    end

    if open then
        reaper.defer(main_loop)
    else
        cleanup()
    end
end

function cleanup()
    if ctx then
        reaper.ImGui_DestroyContext(ctx)
        ctx = nil
    end
end
```

**Kryteria akceptacji**:
- [ ] Okno otwiera się z menu Actions
- [ ] Okno jest dokowalne w Reaper
- [ ] Zamknięcie okna nie powoduje crash'a
- [ ] Fonty są poprawnie załadowane

---

### 1.2 File Browser Dialog

**Plik**: `Main/ReaMD.lua` (w render_toolbar)

**Zadania**:
1. Przycisk "Open" w toolbarze
2. Natywny dialog wyboru pliku (reaper.GetUserFileNameForRead)
3. Obsługa ścieżek cross-platform
4. Zapamiętywanie ostatnio otwartego folderu

**Implementacja**:

```lua
function open_file_dialog()
    local retval, filename = reaper.GetUserFileNameForRead(
        state.last_directory or "",
        "Open Markdown File",
        "*.md;*.markdown"
    )

    if retval then
        state.file_path = normalize_path(filename)
        state.last_directory = get_directory(filename)
        load_markdown_file(filename)
    end
end

function load_markdown_file(path)
    local file = io.open(path, "r")
    if file then
        state.markdown_content = file:read("*a")
        file:close()
        state.parsed_ast = Parser.parse(state.markdown_content)
    else
        show_error("Cannot open file: " .. path)
    end
end
```

**Kryteria akceptacji**:
- [ ] Dialog otwiera się po kliknięciu "Open"
- [ ] Filtrowanie tylko plików .md/.markdown
- [ ] Ścieżki działają na Windows/macOS/Linux
- [ ] Ostatni folder jest zapamiętywany między sesjami

---

### 1.3 Markdown Parser

**Plik**: `Libs/md_parser.lua`

**Wspierane elementy**:

| Element | Pattern | Priorytet |
|---------|---------|-----------|
| Header H1-H6 | `^(#+)%s*(.*)$` | Wysoki |
| Bold | `%*%*(.-)%*%*` | Wysoki |
| Italic | `%*(.-)%*` lub `_(.-)_` | Wysoki |
| Inline code | `` `(.-)` `` | Wysoki |
| Code block | ` ```lang\n...\n``` ` | Wysoki |
| Unordered list | `^%s*[%*%-]%s+(.*)$` | Wysoki |
| Ordered list | `^%s*(%d+)%.%s+(.*)$` | Wysoki |
| Blockquote | `^>%s*(.*)$` | Średni |
| Link | `%[(.-)%]%((.-)%)` | Średni |
| Horizontal rule | `^%-%-%-+$` lub `^%*%*%*+$` | Niski |
| Image | `!%[(.-)%]%((.-)%)` | Niski (Phase 4) |

**Architektura parsera**:

```lua
-- Parser outputuje AST (Abstract Syntax Tree)
-- Każdy node ma typ i content

local Parser = {}

Parser.NodeTypes = {
    DOCUMENT = "document",
    HEADING = "heading",
    PARAGRAPH = "paragraph",
    TEXT = "text",
    BOLD = "bold",
    ITALIC = "italic",
    CODE_INLINE = "code_inline",
    CODE_BLOCK = "code_block",
    LIST_UNORDERED = "list_ul",
    LIST_ORDERED = "list_ol",
    LIST_ITEM = "list_item",
    BLOCKQUOTE = "blockquote",
    LINK = "link",
    HORIZONTAL_RULE = "hr",
}

function Parser.parse(markdown_text)
    local ast = {
        type = Parser.NodeTypes.DOCUMENT,
        children = {}
    }

    -- 1. Podział na bloki (code blocks, paragraphs, lists)
    -- 2. Parsowanie inline (bold, italic, code, links)
    -- 3. Budowanie drzewa AST

    return ast
end

-- Przykład node'a:
-- {
--     type = "heading",
--     level = 2,
--     children = {
--         {type = "text", content = "Hello "},
--         {type = "bold", children = {{type = "text", content = "World"}}}
--     },
--     line_start = 5,
--     line_end = 5
-- }
```

**Algorytm parsowania**:

1. **Pre-processing**: Normalizacja line endings (CRLF → LF)
2. **Block parsing**:
   - Identyfikacja code blocks (``` ... ```)
   - Identyfikacja list (consecutive items)
   - Identyfikacja blockquotes
   - Pozostałe → paragraphs
3. **Inline parsing** (per block):
   - Bold/Italic (uwaga na nested: `***bold italic***`)
   - Inline code (escape inner patterns)
   - Links
4. **AST construction**: Hierarchiczne drzewo z line numbers

**Edge cases do obsłużenia**:
- Nested formatting: `**bold _and italic_**`
- Escaped characters: `\*not bold\*`
- Code blocks with triple backticks inside
- Empty lines between list items
- Headers without space: `#NoSpace` (NIE parsować jako header)

**Kryteria akceptacji**:
- [ ] Parsuje wszystkie elementy z tabeli powyżej
- [ ] Zachowuje numery linii (dla scroll sync)
- [ ] Obsługuje nested formatting
- [ ] Nie crash'uje na malformed input
- [ ] Unit testy pokrywają edge cases

---

### 1.4 Markdown Renderer

**Plik**: `Libs/md_renderer.lua`

**Zadania**:
1. Rekurencyjne renderowanie AST do ImGui
2. Przełączanie fontów per node type
3. Kolorowanie (headers, code, links)
4. Obsługa scroll (ImGui_SetScrollY)

**Mapowanie AST → ImGui**:

| Node Type | ImGui Function | Styl |
|-----------|---------------|------|
| heading | PushFont + TextColored | h1=24px blue, h2=20px, h3=18px |
| paragraph | TextWrapped | normal font |
| bold | PushFont(bold) | lub PushStyleColor |
| italic | PushFont(italic) | lub Dummy(0,0) hack |
| code_inline | TextColored + background | monospace, gray bg |
| code_block | BeginChild + background | monospace, dark bg |
| list_ul | Bullet + Indent | 20px indent |
| list_ol | Text(number) + Indent | 20px indent |
| blockquote | DrawList line + Indent | left border |
| link | TextColored + underline | blue, clickable |
| hr | Separator() | --- |

**Implementacja**:

```lua
local Renderer = {}

function Renderer.render(ctx, ast, fonts, state)
    reaper.ImGui_PushFont(ctx, fonts.normal)

    for _, node in ipairs(ast.children) do
        Renderer.render_node(ctx, node, fonts, state)
    end

    reaper.ImGui_PopFont(ctx)
end

function Renderer.render_node(ctx, node, fonts, state)
    if node.type == "heading" then
        Renderer.render_heading(ctx, node, fonts, state)
    elseif node.type == "paragraph" then
        Renderer.render_paragraph(ctx, node, fonts, state)
    -- ... inne typy
    end
end

function Renderer.render_heading(ctx, node, fonts, state)
    local font_map = {
        [1] = fonts.h1,
        [2] = fonts.h2,
        [3] = fonts.h3,
    }
    local font = font_map[node.level] or fonts.normal
    local color = 0x3366CCFF  -- Blue

    reaper.ImGui_PushFont(ctx, font)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), color)

    Renderer.render_inline(ctx, node.children, fonts, state)

    reaper.ImGui_PopStyleColor(ctx)
    reaper.ImGui_PopFont(ctx)
    reaper.ImGui_Spacing(ctx)
end
```

**Bold/Italic fonts - ROZWIĄZANE (ReaImGui v0.10+)**

ReaImGui v0.10+ wspiera flagi fontów `ImGui_FontFlags_Bold()` i `ImGui_FontFlags_Italic()`:

```lua
-- Tworzenie fontów z flagami
fonts.bold = reaper.ImGui_CreateFont('sans-serif', 14,
    reaper.ImGui_FontFlags_Bold())
fonts.italic = reaper.ImGui_CreateFont('sans-serif', 14,
    reaper.ImGui_FontFlags_Italic())
fonts.bold_italic = reaper.ImGui_CreateFont('sans-serif', 14,
    reaper.ImGui_FontFlags_Bold() | reaper.ImGui_FontFlags_Italic())

-- Użycie w renderze
reaper.ImGui_PushFont(ctx, fonts.bold)
reaper.ImGui_Text(ctx, "Bold text")
reaper.ImGui_PopFont(ctx)
```

**Opcjonalnie dla code blocks**: Bundled monospace font (JetBrains Mono) dla gwarantowanej konsystencji.

**Kryteria akceptacji**:
- [ ] Wszystkie node types renderują się poprawnie
- [ ] Headers mają różne rozmiary i kolory
- [ ] Code blocks mają tło
- [ ] Scroll działa płynnie
- [ ] Links są klikalne (otwierają w przeglądarce)

---

### 1.5 Scroll & Content Area

**Implementacja scrollable content**:

```lua
function render_content(ctx, state, fonts)
    local child_flags = reaper.ImGui_WindowFlags_HorizontalScrollbar()

    if reaper.ImGui_BeginChild(ctx, 'content', -1, -1, false, child_flags) then
        -- Track scroll position for scenario sync
        state.scroll_y = reaper.ImGui_GetScrollY(ctx)
        state.scroll_max_y = reaper.ImGui_GetScrollMaxY(ctx)

        Renderer.render(ctx, state.parsed_ast, fonts, state)

        -- Programmatic scroll (for scenario mode)
        if state.scroll_to_line then
            local y = calculate_y_for_line(state.scroll_to_line)
            reaper.ImGui_SetScrollY(ctx, y)
            state.scroll_to_line = nil
        end

        reaper.ImGui_EndChild(ctx)
    end
end
```

**Performance dla dużych dokumentów**:

Dla dokumentów >1000 linii użyj `ImGui_ListClipper`:

```lua
function render_with_clipper(ctx, lines, fonts)
    local clipper = reaper.ImGui_CreateListClipper(ctx)
    reaper.ImGui_ListClipper_Begin(clipper, #lines)

    while reaper.ImGui_ListClipper_Step(clipper) do
        local display_start = reaper.ImGui_ListClipper_GetDisplayRange(clipper)
        local display_end = select(2, reaper.ImGui_ListClipper_GetDisplayRange(clipper))

        for i = display_start, display_end - 1 do
            render_line(ctx, lines[i + 1], fonts)
        end
    end
end
```

---

## PHASE 2: Scenario Mode

### 2.1 Region Detection Engine

**Plik**: `Libs/scenario_engine.lua`

**Architektura**:

```lua
local ScenarioEngine = {
    enabled = false,
    regions = {},           -- Cache of project regions
    fragment_map = {},      -- region_id -> {line_start, line_end, heading}
    current_region = -1,    -- Currently playing region
    last_update_time = 0,
}

function ScenarioEngine.init()
    ScenarioEngine.refresh_regions()
end

function ScenarioEngine.refresh_regions()
    ScenarioEngine.regions = {}
    local num_markers, num_regions = reaper.CountProjectMarkers(0)

    for i = 0, num_markers + num_regions - 1 do
        local retval, isrgn, pos, rgnend, name, markrgnindexnumber, color =
            reaper.EnumProjectMarkers3(0, i)

        if retval and isrgn then
            table.insert(ScenarioEngine.regions, {
                idx = markrgnindexnumber,
                pos = pos,
                rgnend = rgnend,
                name = name,
                color = color
            })
        end
    end
end

function ScenarioEngine.get_current_region()
    if reaper.GetPlayState() & 1 ~= 1 then
        return nil  -- Not playing
    end

    local pos = reaper.GetPlayPosition2(0)
    local _, region_idx = reaper.GetLastMarkerAndCurRegion(0, pos)

    return region_idx >= 0 and region_idx or nil
end
```

**Throttling updates**:

```lua
local UPDATE_INTERVAL = 0.033  -- ~30fps (wystarczające dla tekstu)

function ScenarioEngine.update()
    local now = reaper.time_precise()

    if now - ScenarioEngine.last_update_time < UPDATE_INTERVAL then
        return false  -- No update needed
    end

    ScenarioEngine.last_update_time = now
    local new_region = ScenarioEngine.get_current_region()

    if new_region ~= ScenarioEngine.current_region then
        ScenarioEngine.current_region = new_region
        return true  -- Region changed
    end

    return false
end
```

---

### 2.2 Fragment-to-Region Linking

**Data Model**:

```lua
-- Stored in Project ExtState
local EXTSTATE_SECTION = "ReaMD"
local EXTSTATE_KEY_MAPPING = "fragment_mapping"

-- Structure:
-- {
--     "markdown_file": "/path/to/script.md",
--     "file_hash": "abc123",  -- For detecting changes
--     "fragments": [
--         {
--             "region_id": 1,
--             "line_start": 1,
--             "line_end": 15,
--             "heading": "Scene 1: Introduction"
--         }
--     ]
-- }
```

**Linking UI**:

Dwa tryby:
1. **Manual linking**: Użytkownik wybiera region i sekcję markdown
2. **Auto-link by name**: Match region name z heading markdown

```lua
function ScenarioEngine.auto_link_by_name(parsed_ast)
    local headings = extract_headings(parsed_ast)

    for _, region in ipairs(ScenarioEngine.regions) do
        for _, heading in ipairs(headings) do
            if fuzzy_match(region.name, heading.text) then
                ScenarioEngine.link_fragment(
                    region.idx,
                    heading.line_start,
                    heading.line_end
                )
            end
        end
    end
end

function fuzzy_match(region_name, heading_text)
    -- Normalize: lowercase, remove punctuation
    local a = region_name:lower():gsub("[^%w%s]", "")
    local b = heading_text:lower():gsub("[^%w%s]", "")

    return a == b or a:find(b, 1, true) or b:find(a, 1, true)
end
```

**Persistence**:

```lua
function ScenarioEngine.save_mapping()
    local data = {
        markdown_file = state.file_path,
        file_hash = calculate_hash(state.markdown_content),
        fragments = ScenarioEngine.fragment_map
    }

    local json_str = json.encode(data)
    reaper.SetProjExtState(0, EXTSTATE_SECTION, EXTSTATE_KEY_MAPPING, json_str)
end

function ScenarioEngine.load_mapping()
    local retval, json_str = reaper.GetProjExtState(0, EXTSTATE_SECTION, EXTSTATE_KEY_MAPPING)

    if retval > 0 and json_str ~= "" then
        local data = json.decode(json_str)

        -- Validate file still matches
        if data.markdown_file == state.file_path then
            ScenarioEngine.fragment_map = data.fragments
            return true
        end
    end

    return false
end
```

---

### 2.3 Auto-scroll & Highlighting

**Scroll to fragment**:

```lua
function ScenarioEngine.scroll_to_fragment(fragment)
    if not fragment then return end

    -- Calculate Y position for line
    local line_height = 20  -- Approximate, should be measured
    local target_y = (fragment.line_start - 1) * line_height

    -- Smooth scroll animation
    state.scroll_animation = {
        from = state.scroll_y,
        to = target_y,
        start_time = reaper.time_precise(),
        duration = 0.3  -- 300ms
    }
end

function update_scroll_animation()
    if not state.scroll_animation then return end

    local anim = state.scroll_animation
    local elapsed = reaper.time_precise() - anim.start_time
    local t = math.min(elapsed / anim.duration, 1)

    -- Ease-out curve
    t = 1 - (1 - t) * (1 - t)

    local new_y = anim.from + (anim.to - anim.from) * t
    state.scroll_to_y = new_y

    if t >= 1 then
        state.scroll_animation = nil
    end
end
```

**Fragment highlighting**:

```lua
function Renderer.render_with_highlight(ctx, ast, fonts, state, highlighted_lines)
    for _, node in ipairs(ast.children) do
        local is_highlighted =
            node.line_start and
            node.line_start >= highlighted_lines.start and
            node.line_end <= highlighted_lines.stop

        if is_highlighted then
            -- Draw background highlight
            local pos = reaper.ImGui_GetCursorScreenPos(ctx)
            local width = reaper.ImGui_GetContentRegionAvail(ctx)
            local height = calculate_node_height(node)

            local draw_list = reaper.ImGui_GetWindowDrawList(ctx)
            reaper.ImGui_DrawList_AddRectFilled(
                draw_list,
                pos, pos + height,
                0x3366CC33  -- Semi-transparent blue
            )
        end

        Renderer.render_node(ctx, node, fonts, state)
    end
end
```

---

### 2.4 Bidirectional Navigation

**Click heading → Jump to region**:

```lua
function Renderer.render_heading_interactive(ctx, node, fonts, state)
    -- ... render heading ...

    if reaper.ImGui_IsItemHovered(ctx) and
       reaper.ImGui_IsMouseDoubleClicked(ctx, 0) then

        local fragment = ScenarioEngine.find_fragment_for_line(node.line_start)
        if fragment then
            local region = ScenarioEngine.find_region(fragment.region_id)
            if region then
                reaper.SetEditCurPos(region.pos, true, false)
            end
        end
    end
end
```

**Right-click menu**:

```lua
function show_heading_context_menu(ctx, node)
    if reaper.ImGui_BeginPopup(ctx, "heading_context") then
        if reaper.ImGui_MenuItem(ctx, "Create Region Here") then
            create_region_for_heading(node)
        end

        if reaper.ImGui_MenuItem(ctx, "Link to Existing Region...") then
            open_region_picker(node)
        end

        if reaper.ImGui_MenuItem(ctx, "Jump to Linked Region") then
            jump_to_linked_region(node)
        end

        reaper.ImGui_EndPopup(ctx)
    end
end
```

---

## PHASE 3: Polish & Distribution

### 3.1 Configuration Panel

**Settings to expose**:

| Setting | Type | Default | Description |
|---------|------|---------|-------------|
| font_size | number | 14 | Base font size |
| font_family | string | "sans-serif" | Normal text font |
| code_font | string | "monospace" | Code block font |
| theme | enum | "light" | light/dark/auto |
| scroll_speed | number | 1.0 | Scroll multiplier |
| highlight_color | color | 0x3366CC33 | Fragment highlight |
| auto_scroll | bool | true | Follow playback |
| scroll_offset | number | 0.3 | Viewport offset (0.3 = 30% from top) |

**Persistence**:

```lua
local CONFIG_SECTION = "ReaMD_Config"

function Config.save()
    for key, value in pairs(Config.settings) do
        reaper.SetExtState(CONFIG_SECTION, key, tostring(value), true)
    end
end

function Config.load()
    for key, default in pairs(Config.defaults) do
        local saved = reaper.GetExtState(CONFIG_SECTION, key)
        if saved ~= "" then
            Config.settings[key] = parse_value(saved, type(default))
        else
            Config.settings[key] = default
        end
    end
end
```

---

### 3.2 Link Handling

**External links**:

```lua
function open_external_link(url)
    -- Requires SWS extension for CF_ShellExecute
    if reaper.CF_ShellExecute then
        reaper.CF_ShellExecute(url)
    else
        -- Fallback: copy to clipboard
        reaper.CF_SetClipboard(url)
        show_notification("Link copied to clipboard (install SWS for auto-open)")
    end
end
```

**Internal links (anchors)**:

```lua
function handle_link_click(url)
    if url:match("^#") then
        -- Internal anchor
        local anchor = url:sub(2)
        scroll_to_anchor(anchor)
    elseif url:match("^https?://") then
        -- External URL
        open_external_link(url)
    elseif url:match("%.md$") then
        -- Relative markdown file
        local full_path = resolve_relative_path(state.file_path, url)
        load_markdown_file(full_path)
    end
end
```

---

### 3.3 Cross-platform Testing

**Checklist**:

| Platform | Test Cases |
|----------|-----------|
| **Windows** | Path separators, font rendering, high DPI |
| **macOS Intel** | Retina display, dark mode detection |
| **macOS ARM** | Same as Intel, M1/M2 compatibility |
| **Linux** | Font fallback, X11 vs Wayland |

**Path utilities**:

```lua
local Utils = {}

Utils.SEP = package.config:sub(1,1)

function Utils.normalize_path(path)
    if Utils.SEP == '\\' then
        return path:gsub('/', '\\')
    else
        return path:gsub('\\', '/')
    end
end

function Utils.join_path(...)
    local parts = {...}
    return table.concat(parts, Utils.SEP)
end

function Utils.get_directory(path)
    return path:match("^(.*)[/\\]")
end

function Utils.get_filename(path)
    return path:match("[/\\]([^/\\]+)$") or path
end
```

---

### 3.4 ReaPack Distribution

**Package header** (w Main/ReaMD.lua):

```lua
-- @description ReaMD - Dockable Markdown Viewer with Timeline Sync
-- @author [YourName]
-- @version 1.0.0
-- @changelog
--   Initial release
-- @provides
--   [main] ReaMD.lua
--   Libs/json.lua
--   Libs/md_parser.lua
--   Libs/md_renderer.lua
--   Libs/scenario_engine.lua
--   Libs/config.lua
--   Libs/utils.lua
--   Fonts/JetBrainsMono-Regular.ttf
-- @link https://github.com/[username]/ReaMD
-- @about
--   # ReaMD - Markdown Viewer for Reaper
--
--   A dockable markdown viewer with timeline synchronization for voice-over,
--   dubbing, and audio production workflows.
--
--   ## Features
--   - Full markdown rendering (headers, lists, code blocks, etc.)
--   - Scenario Mode: sync text with Reaper regions
--   - Auto-scroll during playback
--   - Cross-platform (Windows, macOS, Linux)
```

**Dependencies**:

```lua
-- @requires
--   ReaImGui >= 0.8
--   SWS >= 2.12.1 (optional, for link opening)
```

---

## PHASE 4: Advanced Features (Optional)

### 4.1 Markdown Editing Mode

- Toggle read/edit mode
- Save changes to file
- Syntax highlighting in editor

### 4.2 Auto-generate Regions from Headers

```lua
function auto_create_regions()
    local headings = extract_headings(state.parsed_ast)
    local duration = 10  -- Default region duration

    for i, heading in ipairs(headings) do
        local start_time = (i - 1) * duration
        local end_time = i * duration

        reaper.AddProjectMarker2(
            0,           -- project
            true,        -- isrgn
            start_time,  -- pos
            end_time,    -- rgnend
            heading.text, -- name
            -1,          -- wantidx
            0            -- color
        )
    end

    ScenarioEngine.auto_link_by_name(state.parsed_ast)
end
```

### 4.3 SRT/Subtitle Import

```lua
function import_srt(path)
    local srt_content = read_file(path)
    local subtitles = parse_srt(srt_content)

    for _, sub in ipairs(subtitles) do
        reaper.AddProjectMarker2(
            0,
            true,
            sub.start_time,
            sub.end_time,
            sub.text,
            -1,
            0
        )
    end
end
```

### 4.4 Search Within Document

```lua
function search_document(query)
    local results = {}
    local query_lower = query:lower()

    for _, node in ipairs(state.parsed_ast.children) do
        local text = extract_text(node)
        if text:lower():find(query_lower, 1, true) then
            table.insert(results, {
                line = node.line_start,
                text = text,
                node = node
            })
        end
    end

    return results
end
```

---

## Testing Strategy

### Unit Tests

**Parser tests** (`Tests/test_parser.lua`):

```lua
local tests = {
    -- Basic elements
    {"# Header 1", {type="heading", level=1}},
    {"## Header 2", {type="heading", level=2}},
    {"**bold**", {type="bold"}},
    {"*italic*", {type="italic"}},
    {"`code`", {type="code_inline"}},

    -- Edge cases
    {"#NoSpace", {type="paragraph"}},  -- Should NOT be header
    {"***bold italic***", {type="bold", children={{type="italic"}}}},
    {"\\*escaped\\*", {type="text", content="*escaped*"}},

    -- Lists
    {"- item 1\n- item 2", {type="list_ul", items=2}},
    {"1. first\n2. second", {type="list_ol", items=2}},

    -- Code blocks
    {"```lua\ncode\n```", {type="code_block", lang="lua"}},
}
```

**Renderer tests** (`Tests/test_renderer.lua`):

```lua
-- Mock ReaImGui context for testing
local mock_ctx = create_mock_imgui_context()

function test_heading_renders_with_correct_font()
    local ast = Parser.parse("# Test")
    Renderer.render(mock_ctx, ast, fonts, state)

    assert(mock_ctx.font_pushes[1] == fonts.h1, "Should use H1 font")
end
```

**Scenario tests** (`Tests/test_scenario.lua`):

```lua
function test_region_detection()
    -- Create test project with regions
    reaper.AddProjectMarker2(0, true, 0, 10, "Scene 1", -1, 0)
    reaper.AddProjectMarker2(0, true, 10, 20, "Scene 2", -1, 0)

    ScenarioEngine.init()

    -- Simulate playback at position 5
    reaper.SetEditCurPos(5, false, false)
    local region = ScenarioEngine.get_current_region()

    assert(region.name == "Scene 1", "Should detect Scene 1 at pos 5")
end
```

### Integration Tests

1. **Full workflow test**:
   - Open markdown file
   - Create regions
   - Link fragments
   - Play project
   - Verify auto-scroll

2. **Cross-platform test**:
   - Test on Windows, macOS, Linux
   - Verify font rendering
   - Verify path handling

### Manual Testing Checklist

- [ ] Open .md file via dialog
- [ ] Scroll document manually
- [ ] Create region and link to heading
- [ ] Play project - verify auto-scroll
- [ ] Double-click heading - verify jump to region
- [ ] Click external link - verify opens in browser
- [ ] Change settings - verify persistence
- [ ] Dock window - verify works correctly
- [ ] Undock window - verify works correctly
- [ ] Large file (>1000 lines) - verify performance

---

## Error Handling

### Error Categories

| Category | Handling |
|----------|----------|
| **File I/O** | Show user-friendly error, don't crash |
| **Parsing** | Graceful degradation, show raw text |
| **ReaImGui** | Check ctx validity, cleanup on close |
| **Region API** | Validate indices, refresh cache |
| **JSON** | Validate schema, fallback to defaults |

### Implementation Pattern

```lua
local function safe_call(fn, ...)
    local success, result = pcall(fn, ...)
    if not success then
        log_error(result)
        return nil, result
    end
    return result
end

local function show_error(message)
    reaper.MB(message, "ReaMD Error", 0)
end

local function log_error(message)
    reaper.ShowConsoleMsg("[ReaMD Error] " .. message .. "\n")
end
```

### Defensive Programming

```lua
-- Always check context validity
function main_loop()
    if not ctx then
        return  -- Context was destroyed, exit
    end

    -- Always check file handle
    local file = io.open(path, "r")
    if not file then
        show_error("Cannot open file: " .. path)
        return
    end

    -- Always validate indices
    local region = ScenarioEngine.regions[idx]
    if not region then
        log_error("Invalid region index: " .. idx)
        return
    end
end
```

---

## Performance Considerations

### Defer Loop Optimization

```lua
local frame_time = 1/60  -- Target 60fps
local last_frame = 0

function main_loop()
    local now = reaper.time_precise()

    -- Skip frame if too soon
    if now - last_frame < frame_time then
        reaper.defer(main_loop)
        return
    end

    last_frame = now

    -- ... render logic ...
end
```

### Caching

1. **Parse once**: Cache AST, re-parse only on file change
2. **Region cache**: Refresh on project change, not every frame
3. **Font cache**: Create fonts once at init, reuse

### Large Document Handling

- Use ListClipper for documents >500 lines
- Lazy-load sections if needed
- Consider pagination for very large files

---

## Research Findings (2025-01-07)

### ReaImGui v0.10.0.2 (September 2025)

**Bold/Italic rozwiązane** - ReaImGui wspiera flagi fontów:

```lua
-- System fonts z flagami bold/italic
local fonts = {
    normal = reaper.ImGui_CreateFont('sans-serif', 14),
    bold = reaper.ImGui_CreateFont('sans-serif', 14,
        reaper.ImGui_FontFlags_Bold()),
    italic = reaper.ImGui_CreateFont('sans-serif', 14,
        reaper.ImGui_FontFlags_Italic()),
    bold_italic = reaper.ImGui_CreateFont('sans-serif', 14,
        reaper.ImGui_FontFlags_Bold() | reaper.ImGui_FontFlags_Italic()),
}
```

**Defer loop limitation**: REAPER's defer runs at ~30-33Hz maximum (nie 60fps). Wystarczające dla text sync.

**ListClipper API**:
- `ImGui_CreateListClipper(ctx)`
- `ImGui_ListClipper_Begin(clipper, items_count, item_height)`
- `ImGui_ListClipper_Step(clipper)` → returns bool
- `ImGui_ListClipper_GetDisplayStart/End(clipper)`
- `ImGui_ListClipper_End(clipper)`

### ReaPack Distribution

**UWAGA**: ReaPack NIE ma `@requires` tag dla runtime dependencies!

Strategie:
1. **Bundle dependencies** - Include files via `@provides`
2. **Runtime check** - Gracefully fail if missing
3. **Document** - Use `@about` to list requirements

```lua
-- Runtime check for ReaImGui
if not reaper.ImGui_CreateContext then
    reaper.MB("ReaImGui extension required", "ReaMD Error", 0)
    return
end
```

### Inline Code Background

ImGui nie wspiera per-character background colors. Opcje:
1. `TextColored()` - tylko zmiana koloru tekstu
2. Mały child window z background
3. Akceptacja braku tła dla inline code

**Rekomendacja**: Użyć child window dla code blocks, tylko kolor dla inline code.

---

## Open Questions

- [x] **RESOLVED**: Obsługa bold/italic → Użyć `ImGui_FontFlags_Bold()` i `ImGui_FontFlags_Italic()`

- [x] **RESOLVED**: Bundlować fonty? → System fonts z flagami fontów dla cross-platform

- [ ] **UNCONFIRMED**: SWS dependency?
  - Wymagane dla `CF_ShellExecute` (link opening)
  - Można zrobić fallback (copy to clipboard)
  - **Rekomendacja**: Optional dependency, graceful fallback

---

## Agent Coordination Rules

### CRITICAL: Sequential vs Parallel Agent Execution

**ZASADA NADRZĘDNA**: Nigdy nie uruchamiaj wielu agentów równolegle, jeśli kod który piszą jest od siebie zależny.

#### Kiedy SEKWENCYJNIE (jeden agent po drugim):

| Sytuacja | Powód |
|----------|-------|
| Parser + Renderer | Renderer zależy od AST structure z Parsera |
| Config + Modules | Moduły importują Config |
| Main + Libs | Main wymaga znajomości API bibliotek |
| Tests + Implementation | Testy muszą znać implementację |

#### Kiedy RÓWNOLEGLE (tylko jeśli 100% niezależne):

| Sytuacja | Powód |
|----------|-------|
| Utils.lua + json.lua (bundled) | Zero zależności między nimi |
| README + Fonts bundling | Dokumentacja vs zasoby |
| Windows tests + Linux tests | Różne środowiska, ten sam kod |

### Wymagana świadomość codebase

**PRZED pisaniem kodu agent MUSI**:

1. **Przeczytać istniejący kod** - nie zgadywać API
2. **Sprawdzić interfejsy** - jakie funkcje/struktury już istnieją
3. **Zrozumieć kontekst** - jak moduł wpasowuje się w całość

```
❌ BŁĄD: Spawn Agent("Write md_parser.lua") || Spawn Agent("Write md_renderer.lua")
         → Renderer nie wie jakie AST structure parser wyprodukuje!

✓ DOBRZE:
   1. Agent A → pisze md_parser.lua → commituje
   2. Agent B → CZYTA md_parser.lua → rozumie AST → pisze md_renderer.lua
```

### Wzorzec koordynacji

```
┌─────────────────────────────────────────────────────────────────┐
│  SEQUENTIAL DEPENDENCY CHAIN (użyj tej kolejności!)            │
│                                                                 │
│  1. utils.lua (zero deps)                                       │
│       ↓                                                         │
│  2. config.lua (imports: utils)                                 │
│       ↓                                                         │
│  3. md_parser.lua (imports: utils) → DEFINIUJE AST STRUCTURE    │
│       ↓                                                         │
│  4. md_renderer.lua (imports: parser, config) → ZUŻYWA AST      │
│       ↓                                                         │
│  5. scenario_engine.lua (imports: renderer, config)             │
│       ↓                                                         │
│  6. Main/ReaMD.lua (imports: ALL)                              │
│       ↓                                                         │
│  7. Tests (imports: modules being tested)                       │
└─────────────────────────────────────────────────────────────────┘
```

### Checkpoint pattern

Po każdym module agent powinien:

```lua
-- CHECKPOINT: md_parser.lua complete
-- Exported interface:
--   Parser.parse(markdown_text) -> AST
--   Parser.NodeTypes = {HEADING, PARAGRAPH, TEXT, BOLD, ...}
--
-- AST Node structure:
--   {type, level?, children?, text?, style?, line_start, line_end}
--
-- NEXT AGENT: Read this before implementing md_renderer.lua
```

---

## Implementation Order

```
Phase 1.1: Window Setup          ← START HERE
    ↓
Phase 1.3: Parser (basic)
    ↓
Phase 1.4: Renderer (basic)
    ↓
Phase 1.2: File Dialog
    ↓
Phase 1.5: Scroll                ← MVP CHECKPOINT
    ↓
Phase 2.1: Region Detection
    ↓
Phase 2.2: Fragment Linking
    ↓
Phase 2.3: Auto-scroll
    ↓
Phase 2.4: Bidirectional Nav     ← SCENARIO MODE COMPLETE
    ↓
Phase 3.1: Config Panel
    ↓
Phase 3.2: Link Handling
    ↓
Phase 3.3: Cross-platform Test
    ↓
Phase 3.4: ReaPack Package       ← RELEASE READY
```

---

## Resources

- [ReaImGui Documentation](https://github.com/cfillion/reaimgui)
- [ReaImGui Forum Thread](https://forum.cockos.com/showthread.php?t=250419)
- [rxi/json.lua](https://github.com/rxi/json.lua)
- [ReaPack Documentation](https://reapack.com/user-guide)
- [ReaScript API](https://www.reaper.fm/sdk/reascript/reascripthelp.html)
- [Dear ImGui](https://github.com/ocornut/imgui) (upstream reference)

---

## Changelog

| Date | Change |
|------|--------|
| 2025-01-07 | Initial plan created |
