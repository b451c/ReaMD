# Building a Dockable Markdown Viewer for Reaper DAW

A dockable markdown viewer with timeline synchronization for Reaper is technically feasible and fills a genuine gap in the ecosystem. **ReaImGui with a custom Lua markdown parser** is the recommended stack, offering full cross-platform support, rich text rendering, and seamless integration with Reaper's defer loop for real-time playback sync.

## Technical feasibility: strong foundation exists

The core requirements align well with available APIs. ReaImGui provides modern GUI widgets including text wrapping, font switching, color styling, and native docking—exactly what markdown rendering demands. Reaper's marker/region API offers `GetLastMarkerAndCurRegion()` for detecting the current timeline position, and `SetProjExtState()` enables persistent metadata storage within project files. No existing tool combines markdown rendering with timeline sync, making this a valuable addition to the Reaper ecosystem.

---

## Recommended technology stack

### GUI framework: ReaImGui (definitive choice)

ReaImGui wraps Dear ImGui for ReaScript, providing **hundreds of widgets**, hardware-accelerated rendering, and cross-platform support (Windows, macOS ARM/Intel, Linux x86/ARM). The native `gfx.*` API requires manual implementation of text wrapping, scrolling, and styling—impractical for markdown rendering.

**Key ReaImGui advantages for this project:**
- Multiple font attachments (essential for headers, bold, code blocks)
- Built-in `TextWrapped()`, `TextColored()`, `Separator()`, `Indent()`
- Native docking via `ImGui_ConfigFlags_DockingEnable()`
- Automatic font fallback for missing glyphs (v0.10+)
- ~60fps rendering with proper defer loop structure

```lua
-- Basic dockable window setup
local ctx = reaper.ImGui_CreateContext('Markdown Viewer', 
  reaper.ImGui_ConfigFlags_DockingEnable())

local font_h1 = reaper.ImGui_CreateFont('sans-serif', 24)
local font_h2 = reaper.ImGui_CreateFont('sans-serif', 20)
local font_normal = reaper.ImGui_CreateFont('sans-serif', 14)
local font_code = reaper.ImGui_CreateFont('monospace', 13)

reaper.ImGui_Attach(ctx, font_h1)
reaper.ImGui_Attach(ctx, font_h2)
reaper.ImGui_Attach(ctx, font_normal)
reaper.ImGui_Attach(ctx, font_code)
```

### Markdown parsing: custom Lua parser or luamd

External Lua parsers with C dependencies (lunamark, lua-discount) won't work in ReaScript's sandboxed environment. Two viable approaches exist:

| Approach | Pros | Cons |
|----------|------|------|
| **luamd** (bakpakin/luamd) | Single-file pure Lua, covers basic features | Outputs HTML requiring conversion |
| **Custom parser** | Direct ImGui output, full control, ~400 LOC | Requires implementation effort |

**Recommended: Custom parser** outputting ImGui render commands directly, avoiding HTML intermediate. Essential patterns:

```lua
local patterns = {
  header = "^(#+)%s*(.*)$",
  bold = "%*%*(.-)%*%*",
  italic = "%*(.-)%*",
  link = "%[(.-)%]%((.-)%)",
  inline_code = "`(.-)`",
  code_block = "```(%w*)%s*(.-)```",
  ul_item = "^%s*[%*%-]%s+(.*)$",
  ol_item = "^%s*(%d+)%.%s+(.*)$",
}
```

### Data format: JSON with rxi/json.lua

For marker-to-text linking, use **rxi/json.lua**—a compact (9KB), pure-Lua JSON library with proper error handling. Store sync data in an external JSON file with a reference path in project ExtState:

```lua
-- Sync data structure
{
  "version": "1.0",
  "markdown_file": "/path/to/script.md",
  "fragments": [
    {"region_id": 1, "line_start": 1, "line_end": 15, "heading": "Scene 1"},
    {"region_id": 2, "line_start": 16, "line_end": 42, "heading": "Scene 2"}
  ]
}
```

---

## Core API reference for implementation

### Playback position and region detection

| Function | Purpose |
|----------|---------|
| `GetPlayPosition2()` | Get position being processed (use for visual sync) |
| `GetPlayState()` | Bitfield: &1=playing, &2=paused, &4=recording |
| `GetLastMarkerAndCurRegion(proj, time)` | Returns last marker index + current region index |
| `EnumProjectMarkers3(proj, idx)` | Get marker/region details: position, name, color |
| `CountProjectMarkers(proj)` | Get total marker and region counts |

### Metadata storage

| Function | Purpose |
|----------|---------|
| `SetProjExtState(proj, section, key, value)` | Store data in project file |
| `GetProjExtState(proj, section, key)` | Retrieve project-embedded data |
| `EnumProjExtState(proj, section, idx)` | Iterate all keys in a section |

### Real-time monitoring pattern

```lua
local last_region = -1
local UPDATE_THRESHOLD = 0.016  -- ~60fps

function monitor_loop()
    if reaper.GetPlayState() & 1 == 1 then  -- Playing
        local pos = reaper.GetPlayPosition2()
        local _, region_idx = reaper.GetLastMarkerAndCurRegion(0, pos)
        
        if region_idx >= 0 and region_idx ~= last_region then
            last_region = region_idx
            local _, isrgn, rpos, rend, name = reaper.EnumProjectMarkers3(0, region_idx)
            highlight_fragment(name)  -- Update markdown display
        end
    end
    reaper.defer(monitor_loop)
end
```

---

## Scenario mode architecture

The "Scenario Mode" feature syncs markdown fragments to Reaper regions. When the playhead enters a region, the viewer automatically scrolls to and highlights the corresponding text section.

### Data model design

```lua
local ScenarioDocument = {
    markdown_path = "",
    parsed_content = {},      -- Cached parsed markdown
    fragment_map = {},        -- region_id -> {line_start, line_end, heading}
    current_fragment = nil,   -- Currently highlighted fragment
}

-- Fragment assignment workflow:
-- 1. User loads markdown file
-- 2. Parser identifies section boundaries (headers)
-- 3. User creates Reaper region for each section
-- 4. Script stores region_id -> section mapping in project ExtState
-- 5. On playback, detect current region and scroll to mapped section
```

### Region-to-text linking options

| Method | Implementation | Persistence |
|--------|---------------|-------------|
| **Region name encoding** | `SCENE:intro\|FRAG:1` in region name | Project file |
| **Project ExtState** | `SetProjExtState(0, "MDViewer", "region_1", "line:15-42")` | Project file |
| **External JSON** | Sidecar file with full fragment data | Separate file |

**Recommended: Hybrid**—store a unique ID in region names, full fragment data in project ExtState for portability.

---

## Cross-platform implementation checklist

### Path handling

```lua
local sep = package.config:sub(1,1)  -- '\' on Windows, '/' on Unix

function normalize_path(path)
    if sep == '\\' then
        return path:gsub('/', '\\')
    else
        return path:gsub('\\', '/')
    end
end

function join_path(...)
    return table.concat({...}, sep)
end
```

### Font strategy

ReaImGui v0.10+ automatically resolves system fonts and falls back for missing glyphs. Use generic family names for maximum compatibility:

```lua
reaper.ImGui_CreateFont('sans-serif', 14)   -- System UI font
reaper.ImGui_CreateFont('monospace', 13)    -- System monospace
```

For guaranteed consistency, bundle a TTF file (e.g., JetBrains Mono for code blocks) and load via `ImGui_CreateFontFromFile()`.

### ReaPack distribution

```lua
-- Script header for ReaPack
-- @description Markdown Viewer with Scenario Mode
-- @author YourName
-- @version 1.0.0
-- @provides
--   [main] MarkdownViewer.lua
--   Libs/json.lua
--   Libs/md_parser.lua
-- @link https://github.com/yourname/reaper-markdown-viewer
```

---

## Existing ecosystem context

No native markdown viewer exists for Reaper—this fills a genuine gap. Related tools:

| Tool | Features | Gap Addressed |
|------|----------|---------------|
| **HeDa Notes Reader** | Plain text display from item notes, karaoke mode | No markdown, no file browsing |
| **X-Raym Rythmoband** | Scrolling text sync (web interface, €30-150) | Requires browser, no markdown |
| **SWS Notes Window** | Basic text display | No timeline sync, no formatting |

Professional dubbing workflows (Mosaic Studio, VoiceQ, Nuendo ADR) handle script sync via specialized proprietary tools at $200+/month. A free, open-source Reaper solution addresses the indie/podcast/small studio segment.

---

## Recommended project structure

```
MarkdownViewer/
├── Main/
│   └── MarkdownViewer.lua       -- Entry point (Actions menu)
├── Libs/
│   ├── json.lua                 -- rxi/json.lua (bundled)
│   ├── md_parser.lua            -- Custom markdown parser
│   ├── renderer.lua             -- ImGui rendering logic
│   ├── scenario.lua             -- Timeline sync logic
│   └── config.lua               -- User preferences
├── Fonts/
│   └── JetBrainsMono-Regular.ttf
└── README.md
```

### Module loading

```lua
local info = debug.getinfo(1, 'S')
local script_dir = info.source:match('@?(.+)'):match('^(.+)[/\\]')
package.path = script_dir .. '/Libs/?.lua;' .. package.path

local json = require('json')
local Parser = require('md_parser')
local Renderer = require('renderer')
```

---

## Development roadmap

### Phase 1: Core viewer (2-3 days)
- ReaImGui dockable window setup
- File browser dialog for .md selection
- Basic markdown parser (headers, bold, italic, lists, code blocks)
- Scrollable content rendering with font switching

### Phase 2: Scenario mode (2-3 days)
- Region enumeration and caching
- Real-time playback monitoring via defer loop
- Fragment-to-region linking UI
- Auto-scroll and highlighting on region entry
- Project ExtState persistence

### Phase 3: Polish (1-2 days)
- Link handling (open URLs via `reaper.CF_ShellExecute()`)
- Configuration panel (font size, colors, scroll behavior)
- Cross-platform testing
- ReaPack packaging

### Phase 4: Advanced features (optional)
- Markdown editing mode
- Auto-generate regions from markdown headers
- SRT/subtitle import as regions
- Search within document

---

## Potential challenges and mitigations

| Challenge | Mitigation |
|-----------|-----------|
| **Bold/italic fonts** | ImGui requires separate font files; load Arial Bold/Italic or bundle fonts |
| **Large documents** | Use `ImGui_ListClipper` for virtualized rendering |
| **33Hz defer limit** | Sufficient for text sync; use position thresholds to avoid redundant updates |
| **Region detection performance** | Cache regions at script start; use binary search for 100+ regions |
| **Cross-platform paths** | Always normalize with `package.config:sub(1,1)` |
| **Code block highlighting** | Monospace font + background color; syntax highlighting is complex—consider v2 |

---

## UI/UX recommendations

### Layout

```
┌─────────────────────────────────────────────┐
│ 📂 Open │ 🔗 Sync │ ⚙️ Settings │ [file.md]│  <- Toolbar
├─────────────────────────────────────────────┤
│ # Scene 1: Introduction                     │
│                                             │
│ This is the **opening monologue** for the   │
│ documentary. The narrator should speak      │
│ slowly and clearly.                         │
│                                             │
│ > Note: Pause 2 seconds after this section  │
│                                             │  <- Scrollable content
│ ┌─────────────────────────────────────────┐ │
│ │ ## Scene 2: Interview Setup ◀ PLAYING   │ │  <- Highlighted region
│ │                                         │ │
│ │ Interviewer: Welcome to the show...     │ │
│ └─────────────────────────────────────────┘ │
│                                             │
│ ## Scene 3: B-Roll Description              │
└─────────────────────────────────────────────┘
```

### Interaction patterns

- **Double-click region indicator** → Jump Reaper playhead to region start
- **Right-click heading** → Create/link Reaper region from selection
- **Scroll wheel** → Navigate document (decoupled from playback when paused)
- **Play button** → Lock scroll to follow playhead

---

## Code architecture summary

```
┌──────────────────┐     ┌──────────────────┐
│  Main Entry      │────▶│  GUI Manager     │
│  (defer loop)    │     │  (ReaImGui)      │
└────────┬─────────┘     └────────┬─────────┘
         │                        │
         ▼                        ▼
┌──────────────────┐     ┌──────────────────┐
│  Scenario Engine │◀───▶│  Markdown        │
│  (playback sync) │     │  Renderer        │
└────────┬─────────┘     └────────┬─────────┘
         │                        │
         ▼                        ▼
┌──────────────────┐     ┌──────────────────┐
│  Reaper API      │     │  Parser          │
│  (markers,       │     │  (custom Lua)    │
│   regions, pos)  │     │                  │
└──────────────────┘     └──────────────────┘
```

This architecture cleanly separates concerns: the main loop coordinates GUI updates and scenario monitoring, while specialized modules handle markdown parsing, rendering, and Reaper API interaction. The parser outputs a structured AST that the renderer converts to ImGui calls, and the scenario engine maps region changes to scroll positions.

---

## Conclusion

Building a markdown viewer with scenario mode for Reaper is well-supported by the available APIs. **ReaImGui + custom Lua parser + JSON metadata** provides the most maintainable, cross-platform solution. The primary development effort lies in the markdown parser (~400 LOC) and the scenario synchronization logic. With ReaPack distribution, the tool can reach the broader Reaper community—addressing a clear gap in the ecosystem for voice-over, dubbing, and audio production workflows.