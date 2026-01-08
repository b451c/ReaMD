---
date: 2026-01-07T23:26:16+01:00
session_name: reamd-planning
researcher: Claude
git_commit: N/A (not a git repo)
branch: N/A
repository: ReaMD
topic: "ReaMD Scenario Mode & Text Selection Implementation"
tags: [reaimgui, lua, reaper, markdown-viewer, scenario-mode]
status: complete
last_updated: 2026-01-07
last_updated_by: Claude
type: implementation_strategy
root_span_id:
turn_span_id:
---

# Handoff: ReaMD Scenario Mode Complete with Save/Load

## Task(s)

| Task | Status |
|------|--------|
| Implement reverse scenario linking (element → region picker) | Completed |
| Add Region column to tables in scenario mode | Completed |
| Add region dropdown for headings | Completed |
| Fix scenario tracking bugs (auto_scroll blocking, Lua operator precedence) | Completed |
| Implement text selection mode (Select: ON/OFF toggle) | Completed |
| Save scenario mappings to MD file | Completed |
| Auto-load scenario from MD file on open | Completed |

Working from continuity ledger: `thoughts/ledgers/CONTINUITY_CLAUDE-reamd-planning.md`

## Critical References

1. `thoughts/ledgers/CONTINUITY_CLAUDE-reamd-planning.md` - Full project state and decisions
2. `Main/ReaMD.lua` - Main application entry point
3. `Libs/scenario_engine.lua` - All scenario/region sync logic

## Recent changes

- `Libs/scenario_engine.lua:195-296` - New fragment structure with `node_type`, `identifier`, `row_index`
- `Libs/scenario_engine.lua:282-296` - New helper functions: `find_fragment_by_line()`, `unlink_fragment_by_line()`, `get_region_name()`, `format_region_display()`
- `Libs/scenario_engine.lua:425-540` - File persistence: `save_to_file()`, `load_from_file()`, `file_has_scenario_data()`, `strip_reamd_marker()`
- `Libs/scenario_engine.lua:131-156` - Fixed `get_current_region()` play state check (Lua operator precedence bug)
- `Libs/scenario_engine.lua:432-469` - Fixed `update()` to always track/highlight regardless of `auto_scroll` setting
- `Libs/md_renderer.lua:244-345` - Added `render_region_selector()` for dropdown UI
- `Libs/md_renderer.lua:700-759` - Modified `render_table()` to add Region column when scenario ON
- `Libs/md_renderer.lua:324-331` - Added region dropdown after headings in scenario mode
- `Main/ReaMD.lua:500-520` - Added "Save Scenario" button in toolbar
- `Main/ReaMD.lua:507-520` - Added "Select Mode" toggle button
- `Main/ReaMD.lua:247-311` - Updated `load_markdown_file()` for auto-detect and auto-enable scenario
- `Main/ReaMD.lua:565-588` - Added select mode rendering with `InputTextMultiline`

## Learnings

### ReaImGui v0.10 API
- `CreateFont(family)` - no size parameter, size goes to `PushFont(ctx, font, size)`
- `BeginChild(ctx, id, w, h, child_flags, window_flags)` - different signature from v0.9
- `InputTextMultiline` with `InputTextFlags_ReadOnly()` allows text selection/copy

### Lua Gotchas
- Bitwise `&` operator has lower precedence than `==` in Lua 5.3+
- `play_state & 1 == 0` evaluates as `play_state & (1 == 0)` not `(play_state & 1) == 0`
- Solution: use simple equality checks like `play_state == 1 or play_state == 5`

### ReaImGui Table Columns
- Dynamic column count works: `BeginTable(ctx, id, total_cols, flags)`
- Extra columns can be added conditionally based on state

### Scenario File Format
```html
<!-- reamd-scenario:{"fragments":[...]}:reamd -->
```
- Invisible in normal markdown viewers
- Parsed and stripped when loading in ReaMD

## Post-Mortem

### What Worked
- **Dropdown per element approach**: Clean UI, user picks region from combo box next to each table row/heading
- **File-based persistence**: Storing scenario in MD file itself ensures portability (no dependency on Reaper project)
- **Auto-detection on load**: Checking for `<!-- reamd-scenario:` marker and auto-enabling scenario mode provides seamless UX
- **Separating tracking from scrolling**: `update()` now always tracks/highlights, `auto_scroll` only affects scroll behavior

### What Failed
- **Initial `auto_scroll` check placement**: Blocked ALL tracking when disabled - users couldn't see highlighting even if they wanted manual scroll
- **Lua bitwise operator**: `&` precedence issue caused play state check to always fail
- **Function declaration order**: `render_region_selector` was defined AFTER `render_heading` which called it → nil error

### Key Decisions
- **Decision**: Store scenario data as HTML comment at end of MD file
  - Alternatives: YAML frontmatter, sidecar .json file, only ExtState
  - Reason: Invisible to markdown viewers, no extra files, portable with the document

- **Decision**: Add Region column to tables vs inline button
  - Alternatives: Hover button, sidebar panel, right-click menu
  - Reason: Table-based scenarios are the primary use case, inline column is most visible

- **Decision**: Use `line_start` as fragment key (not region_id)
  - Alternatives: region_id as key, composite key
  - Reason: Multiple elements can't link to same region, but same line is always unique

## Artifacts

- `Main/ReaMD.lua` - Main script with all UI and coordination
- `Libs/scenario_engine.lua` - Scenario sync engine with file persistence
- `Libs/md_renderer.lua` - Markdown renderer with scenario UI
- `Libs/md_parser.lua` - Markdown parser (unchanged this session)
- `Libs/config.lua` - Configuration management
- `Libs/utils.lua` - Utility functions
- `thoughts/ledgers/CONTINUITY_CLAUDE-reamd-planning.md` - Session state ledger

## Action Items & Next Steps

1. **Test scenario playback sync** - Verify highlighting works during Reaper playback with linked regions
2. **Test file save/load cycle** - Save scenario, close Reaper, reopen file, verify auto-enable works
3. **Edge cases to verify**:
   - Multiple V/O entries with same name (row_index disambiguation)
   - Files without tables (only headings)
   - Empty region list (no regions in project)
4. **Potential enhancements**:
   - "Clear All" button to remove all region links
   - Visual indicator showing which regions are already linked
   - Export/import scenario separately from MD file

## Other Notes

### File Structure
```
ReaMD/
├── Main/
│   └── ReaMD.lua          # Entry point, UI, coordination
└── Libs/
    ├── md_parser.lua      # Markdown → AST
    ├── md_renderer.lua    # AST → ReaImGui widgets
    ├── scenario_engine.lua # Region sync, persistence
    ├── config.lua         # Settings management
    ├── utils.lua          # File I/O, path helpers
    └── json.lua           # JSON encode/decode
```

### How Scenario Mode Works
1. User enables Scenario mode → `refresh_regions()` scans Reaper project
2. Tables show extra "Region" column with dropdowns
3. User selects region for each row → `link_fragment()` stores mapping
4. User clicks "Save Scenario" → writes to MD file as HTML comment
5. During playback, `update()` checks current position → `get_current_region()` → `find_fragment_for_region()` → sets `highlight_lines`
6. Renderer draws highlight background for matched lines

### Testing in Reaper
1. Load script via Actions → ReaScript → Load
2. Run "ReaMD" action
3. Open a markdown file with tables
4. Create regions in Reaper timeline
5. Enable Scenario mode
6. Link regions via dropdowns
7. Play and verify highlighting follows
