# Session: reamd-implementation
Updated: 2026-01-08T02:45:00.000Z

## Goal
Implement ReaMD (Dockable Markdown Viewer for Reaper DAW) with full markdown support + scenario mode.
Done when: script runs, renders markdown, themes work, **multi-item scenario linking** works.

## Constraints
- Technology stack: ReaImGui + Custom Lua Parser + JSON
- Must support ReaImGui v0.10+ API (breaking changes from v0.9)
- Cross-platform: Windows, macOS, Linux
- SWS extension optional (fallback via GetItemStateChunk)

## Key Decisions
- **Fonts v0.10**: CreateFont(family) without size, size goes to PushFont(ctx, font, size)
- **BeginChild v0.10**: (ctx, id, w, h, child_flags, window_flags)
- **Theme system**: 14 style colors per theme, unified WindowBg/ChildBg (no visible border)
- **Scenario save**: Separate .reamd file (not embedded in MD)
- **TableSetBgColor**: For row highlighting, color format 0xRRGGBBAA
- **Item-based linking v3**: Multi-item per fragment, item_guids array
- **Color categories**: V/M/F/O labels on colored buttons for VO/Music/FX/Other
- **Group support**: Items in Reaper group treated as one unit when linking
- **Teleprompter v3**: VO-only, centered, progress bar, group-aware

## State
- Done:
  - [x] All Lua modules (Main + 8 Libs)
  - [x] ReaImGui v0.10 API compatibility
  - [x] TABLE support (parser + renderer)
  - [x] Theme system (dark + light) - unified bg colors
  - [x] **Multi-item linking v3** - item_guids array
  - [x] **Color categories** - V/M/F/O buttons
  - [x] **Group support** - Reaper item groups treated as one
  - [x] **Teleprompter v3** - all improvements (see below)
- Now: Feature complete, production testing
- Next: User feedback, potential enhancements

## Teleprompter v3 (this session)
- [x] **User-controlled size** - no auto-resize, persisted
- [x] **VO-only hold** - 2 second hold prevents flashing
- [x] **VO-only main text** - FX/Music as small indicators
- [x] **Centered text** - horizontal and vertical centering
- [x] **Font size 48px** - large readable text
- [x] **50% opacity** - semi-transparent background
- [x] **No border/separator** - clean minimal UI
- [x] **No [V] button** - just text
- [x] **Progress bar** - bottom of window
  - Orange: counting to NEXT VO
  - Green: counting to END of current (last VO)
  - Group-aware: treats grouped items as one unit

## Group Support (this session)
- [x] `get_selected_item()` returns all items in Reaper group
- [x] Clicking [+] on grouped item adds ALL items from group
- [x] Progress bar calculates earliest start / latest end for groups
- [x] Playback treats group as one fragment

## Open Questions
- CONFIRMED: All features working in production

## Working Set
- Branch: (none - not git repo)
- Key files:
  - `Libs/teleprompter.lua` - v3: progress bar, centering, groups
  - `Libs/scenario_engine.lua` - group support in get_selected_item
  - `Libs/md_renderer.lua` - links all items from group
  - `Main/ReaMD.lua` - unified theme colors

## UI Summary

**Teleprompter Window (v3):**
```
┌─────────────────────────────────────────────────┐
│                                                 │
│         Main VO dialog text (centered)          │
│                                                 │
│   M: Music cue  F: Sound effect                 │
│ ████████████████░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ │
└─────────────────────────────────────────────────┘
```
- 50% opacity, no border
- Text centered horizontally and vertically
- Font size 48px
- Progress bar: orange (next VO) / green (end of current)
- Group-aware countdown

## Files Summary

| File | Status |
|------|--------|
| Main/ReaMD.lua | OK - unified theme colors |
| Libs/md_parser.lua | OK |
| Libs/md_renderer.lua | OK - group linking |
| Libs/config.lua | OK |
| Libs/utils.lua | OK |
| Libs/scenario_engine.lua | OK - group support |
| Libs/json.lua | OK |
| Libs/teleprompter.lua | OK - v3 with progress bar |
