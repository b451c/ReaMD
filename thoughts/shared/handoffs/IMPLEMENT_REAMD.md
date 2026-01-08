# Implementation Handoff: ReaMD

> **Mission**: Build production-ready Dockable Markdown Viewer for Reaper DAW

## Quick Start

```
You are the implementation orchestrator for ReaMD.
Your job: Execute the plan, coordinate sub-agents, deliver working software.
```

---

## Required Reading (IN THIS ORDER)

| Priority | File | Purpose |
|----------|------|---------|
| 1 | `docs/Building_ReaMD.md` | Original requirements & API reference |
| 2 | `thoughts/shared/plans/2025-01-07-reamd-implementation.md` | Full implementation plan |
| 3 | This file | Orchestration rules |

**READ THESE FILES BEFORE WRITING ANY CODE.**

---

## Project Overview

**ReaMD** = Dockable Markdown Viewer for Reaper DAW with Timeline Synchronization

**Tech Stack** (already decided - do not change):
- GUI: ReaImGui (Dear ImGui wrapper for ReaScript)
- Parser: Custom Lua (~400 LOC, outputs AST)
- Data: JSON (rxi/json.lua) + Project ExtState
- Language: Lua (ReaScript)

**Target Users**: Voice-over artists, dubbing studios, podcasters

---

## File Structure to Create

```
/Volumes/@Basic/Projekty/ReaMD/
├── Main/
│   └── ReaMD.lua                   # Entry point (Actions menu)
├── Libs/
│   ├── json.lua                    # Bundle rxi/json.lua (download from GitHub)
│   ├── md_parser.lua               # Custom markdown parser
│   ├── md_renderer.lua             # ReaImGui rendering
│   ├── scenario_engine.lua         # Timeline sync
│   ├── config.lua                  # User preferences
│   └── utils.lua                   # Cross-platform utilities
├── Tests/
│   ├── test_parser.lua             # Parser unit tests
│   ├── test_renderer.lua           # Renderer tests (mock ImGui)
│   └── test_scenario.lua           # Scenario engine tests
└── README.md                       # User documentation
```

---

## Implementation Phases

Execute in this exact order:

### Phase 1: Core Viewer
```
1.1 utils.lua        → Cross-platform path handling
1.2 config.lua       → Settings persistence (ExtState)
1.3 md_parser.lua    → Markdown → AST (headers, bold, italic, code, lists)
1.4 md_renderer.lua  → AST → ReaImGui calls
1.5 Main/ReaMD.lua   → Window setup, file dialog, defer loop
```

### Phase 2: Scenario Mode
```
2.1 scenario_engine.lua → Region detection, fragment linking
2.2 Integrate with renderer → Auto-scroll, highlighting
2.3 Bidirectional nav → Click heading → jump to region
```

### Phase 3: Polish
```
3.1 Config panel UI
3.2 Link handling (CF_ShellExecute or clipboard fallback)
3.3 ReaPack header metadata
```

### Phase 4: Testing & Documentation
```
4.1 Unit tests for parser
4.2 Integration tests
4.3 README.md with usage instructions
```

---

## CRITICAL: Agent Coordination Rules

### Rule 1: Sequential Dependency Chain

**NEVER run parallel agents on dependent code.**

```
CORRECT ORDER (sequential):
┌─────────────────────────────────────────────────┐
│ 1. utils.lua       (zero deps)                  │
│      ↓                                          │
│ 2. config.lua      (imports: utils)             │
│      ↓                                          │
│ 3. md_parser.lua   (imports: utils)             │
│      ↓ DEFINES AST STRUCTURE                    │
│ 4. md_renderer.lua (imports: parser, config)    │
│      ↓ CONSUMES AST                             │
│ 5. scenario_engine (imports: renderer, config)  │
│      ↓                                          │
│ 6. Main/ReaMD.lua  (imports: ALL)               │
│      ↓                                          │
│ 7. Tests           (imports: modules tested)    │
└─────────────────────────────────────────────────┘
```

### Rule 2: Full Codebase Awareness

Before spawning ANY sub-agent:

```lua
-- Sub-agent MUST receive:
1. List of existing files to READ first
2. Interfaces/APIs already defined
3. Specific task boundaries
4. Expected output format
```

**Example sub-agent prompt:**
```
Task: Implement md_renderer.lua

FIRST: Read these files:
- Libs/md_parser.lua (understand AST structure)
- Libs/config.lua (understand settings API)

AST Node structure (from parser):
{
  type = "heading"|"paragraph"|"bold"|"italic"|"code_block"|...
  level = 1-6 (for headings)
  children = {} (nested nodes)
  text = "content"
  line_start = number
  line_end = number
}

YOUR TASK: Create Renderer module that:
1. Takes AST and ReaImGui context
2. Recursively renders nodes
3. Handles font switching (PushFont/PopFont)
4. Returns scroll position info

DO NOT modify md_parser.lua.
DO NOT change AST structure.
```

### Rule 3: Checkpoint After Each Module

After completing each file, document its interface:

```lua
-- ═══════════════════════════════════════════════════════
-- CHECKPOINT: md_parser.lua COMPLETE
-- ═══════════════════════════════════════════════════════
-- Exported:
--   Parser.parse(text) → AST
--   Parser.NodeTypes = {HEADING, PARAGRAPH, TEXT, BOLD, ...}
--
-- AST Node: {type, level?, children?, text?, line_start, line_end}
-- ═══════════════════════════════════════════════════════
```

### Rule 4: Parallel Only When 100% Independent

**ALLOWED parallel:**
- Downloading json.lua + creating directory structure
- Writing README + running existing tests
- Different platform tests (same code)

**FORBIDDEN parallel:**
- Parser + Renderer (renderer needs AST structure)
- Config + anything that imports config
- Main entry + any Lib it imports

---

## Key Technical Details

### Font Setup (ReaImGui v0.10+)

```lua
-- Use font flags, NOT separate font files
local fonts = {
    normal = reaper.ImGui_CreateFont('sans-serif', 14),
    bold = reaper.ImGui_CreateFont('sans-serif', 14,
        reaper.ImGui_FontFlags_Bold()),
    italic = reaper.ImGui_CreateFont('sans-serif', 14,
        reaper.ImGui_FontFlags_Italic()),
    h1 = reaper.ImGui_CreateFont('sans-serif', 24,
        reaper.ImGui_FontFlags_Bold()),
    code = reaper.ImGui_CreateFont('monospace', 13),
}

-- MUST attach all fonts to context
for _, font in pairs(fonts) do
    reaper.ImGui_Attach(ctx, font)
end
```

### Defer Loop Pattern

```lua
local function main_loop()
    local visible, open = reaper.ImGui_Begin(ctx, 'ReaMD', true)

    if visible then
        -- Render content
        reaper.ImGui_End(ctx)
    end

    if open then
        reaper.defer(main_loop)  -- Continue loop
    else
        cleanup()  -- Destroy context
    end
end

reaper.defer(main_loop)  -- Start
```

### ReaImGui Dependency Check

```lua
-- MUST be at script start
if not reaper.ImGui_CreateContext then
    reaper.MB(
        "ReaImGui extension required.\n\n" ..
        "Install via ReaPack:\n" ..
        "Extensions > ReaPack > Browse packages > ReaImGui",
        "ReaMD Error", 0
    )
    return
end
```

### AST Structure (Parser Output)

```lua
-- Document node
{
    type = "document",
    children = { ... }
}

-- Heading node
{
    type = "heading",
    level = 2,  -- 1-6
    children = { {type="text", text="Title"} },
    line_start = 5,
    line_end = 5
}

-- Paragraph with mixed formatting
{
    type = "paragraph",
    children = {
        {type = "text", text = "Normal "},
        {type = "bold", children = {{type="text", text="bold"}}},
        {type = "text", text = " text"}
    },
    line_start = 10,
    line_end = 12
}
```

### Region-to-Fragment Mapping

```lua
-- Stored in Project ExtState
local EXTSTATE_SECTION = "ReaMD"

-- Data structure
{
    markdown_file = "/path/to/file.md",
    fragments = {
        {region_id = 1, line_start = 1, line_end = 15, heading = "Scene 1"},
        {region_id = 2, line_start = 16, line_end = 42, heading = "Scene 2"}
    }
}
```

---

## Quality Checklist

Before marking ANY phase complete:

- [ ] Code runs without errors
- [ ] Cross-platform paths (use `package.config:sub(1,1)` for separator)
- [ ] ReaImGui context properly cleaned up on close
- [ ] No hardcoded paths
- [ ] Error handling for file I/O
- [ ] Comments for non-obvious logic only
- [ ] Checkpoint comment at file end

---

## External Resources to Download

| Resource | URL | Destination |
|----------|-----|-------------|
| json.lua | `https://raw.githubusercontent.com/rxi/json.lua/master/json.lua` | `Libs/json.lua` |

---

## Success Criteria

**MVP (Phase 1-2 complete):**
- [ ] Open .md file via dialog
- [ ] Render headers, bold, italic, code blocks, lists
- [ ] Scroll document
- [ ] Create/link regions to markdown sections
- [ ] Auto-scroll during playback
- [ ] Click heading → jump to region

**Production Ready (Phase 3-4 complete):**
- [ ] Settings persist between sessions
- [ ] External links open in browser (or copy to clipboard)
- [ ] Unit tests pass
- [ ] ReaPack package header complete
- [ ] README with installation & usage

---

## Troubleshooting

| Issue | Solution |
|-------|----------|
| "ReaImGui not found" | Install via ReaPack |
| Fonts not rendering | Check `ImGui_Attach()` called for all fonts |
| Window not dockable | Verify `ConfigFlags_DockingEnable` in CreateContext |
| Crash on close | Ensure `ImGui_End()` called before checking `open` |
| Paths fail on Windows | Use `package.config:sub(1,1)` for separator |

---

## Start Command

After reading all required files, begin with:

```
1. Create directory structure
2. Download json.lua
3. Implement utils.lua (first module, zero deps)
4. Continue sequential chain...
```

**Remember: Quality over speed. Each module must be solid before moving to the next.**

---

*This handoff created: 2025-01-07*
*Plan location: thoughts/shared/plans/2025-01-07-reamd-implementation.md*
