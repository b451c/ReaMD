---
date: 2026-01-08T02:37:13+01:00
session_name: reamd-planning
researcher: Claude
git_commit: N/A
branch: N/A
repository: ReaMD
topic: "Teleprompter v3 & Group Support Implementation"
tags: [teleprompter, reaper, lua, reaimgui, groups]
status: complete
last_updated: 2026-01-08
last_updated_by: Claude
type: implementation_strategy
root_span_id:
turn_span_id:
---

# Handoff: Teleprompter v3 & Reaper Item Group Support

## Task(s)

### Completed
1. **Theme fix** - Unified WindowBg/ChildBg colors to eliminate visible border around markdown content
2. **Teleprompter v3** - Major overhaul with all features below:
   - User-controlled size (no auto-resize), persisted to ExtState
   - VO-only hold (2 seconds) prevents flashing between fragments
   - VO-only main text - FX/Music/Other shown as small indicators only
   - Centered text (horizontal + vertical)
   - Font size 48px, 50% opacity
   - No border, no separator, no [V] button - clean minimal UI
   - Progress bar at bottom showing countdown
3. **Reaper Item Group Support** - Items in Reaper groups treated as single unit:
   - `get_selected_item()` returns all GUIDs from item's group
   - Clicking [+] adds all items from group at once
   - Progress bar uses earliest start / latest end for groups
4. **Progress Bar** - Visual countdown indicator:
   - Orange: counting to next VO fragment
   - Green: counting to end of current VO (when last fragment)
   - Group-aware calculations

## Critical References
- `thoughts/ledgers/CONTINUITY_CLAUDE-reamd-planning.md` - Main continuity ledger
- `Libs/teleprompter.lua` - All teleprompter logic
- `Libs/scenario_engine.lua` - Group support in get_selected_item()

## Recent changes

### Main/ReaMD.lua
- Lines 175-178: Unified dark theme WindowBg/ChildBg to 0x252526FF
- Lines 191-195: Unified light theme WindowBg/ChildBg to 0xB8B8B8FF

### Libs/teleprompter.lua
- Line 18: font_size = 48
- Line 19: bg_opacity = 0.5
- Lines 33-37: Added progress_state for countdown bar
- Lines 73-154: Rewrote get_time_to_next_vo() - group-aware, returns time to end of current if last
- Lines 177-178: Disabled loading font_size/opacity from ExtState (use code defaults)
- Lines 248-251: Added WindowBorderSize=0, Border color transparent
- Lines 310-365: Vertical centering of content
- Lines 432-470: Progress bar rendering with color based on next vs end-of-current

### Libs/scenario_engine.lua
- Lines 157-181: Added get_items_in_group() local function
- Lines 183-207: Rewrote get_selected_item() to return all GUIDs from group

### Libs/md_renderer.lua
- Lines 350-371: Updated [+] button handler to add all items from group

## Learnings

1. **ExtState persistence** - Values saved to Reaper ExtState override code defaults. Had to disable loading to apply new values.

2. **ImGui vertical centering** - Calculate content height, then SetCursorPosY to (window_height - content_height) / 2

3. **Reaper groups** - Use `GetMediaItemInfo_Value(item, "I_GROUPID")` to get group ID. Value 0 means not grouped. Iterate all items to find group members.

4. **Progress bar for "last item"** - When no next VO exists, show countdown to end of current fragment. Use different color (green) to indicate this mode.

5. **Hold logic placement** - VO hold must be applied AFTER separating vo_fragments from other_fragments, not before.

## Post-Mortem

### What Worked
- **Incremental changes** - Small focused edits with immediate testing
- **ExtState for persistence** - Position/size survive Reaper restarts
- **DrawList for progress bar** - Clean overlay without affecting layout

### What Failed
- **Tried:** Initial hold logic on all fragments → Failed because: Music/FX kept triggering hold even when VO was gone
- **Tried:** Auto-resize with size constraints → Failed because: Window kept changing size, user couldn't control it
- **Error:** Font size not changing → Fixed by: Disabling ExtState loading for font_size

### Key Decisions
- **Decision:** VO-only in main teleprompter text
  - Alternatives: Show all categories as main text
  - Reason: Cleaner UX, VO is primary use case for prompter

- **Decision:** Progress bar instead of numeric countdown
  - Alternatives: Keep text countdown "5.2s"
  - Reason: Visual indicator more intuitive, less distracting

- **Decision:** Green for "end of current", orange for "next"
  - Alternatives: Single color
  - Reason: User knows if counting to next item or end of session

## Artifacts

- `/Volumes/@Basic/Projekty/ReaMD/thoughts/ledgers/CONTINUITY_CLAUDE-reamd-planning.md` - Updated ledger
- `/Volumes/@Basic/Projekty/ReaMD/Libs/teleprompter.lua` - Teleprompter v3
- `/Volumes/@Basic/Projekty/ReaMD/Libs/scenario_engine.lua:157-207` - Group support
- `/Volumes/@Basic/Projekty/ReaMD/Libs/md_renderer.lua:350-371` - Group linking UI
- `/Volumes/@Basic/Projekty/ReaMD/Main/ReaMD.lua:175-195` - Theme unification

## Action Items & Next Steps

1. **Test in production** - User is actively testing with real projects
2. **Potential enhancements** based on feedback:
   - Adjustable hold duration in settings
   - Adjustable font size in settings (currently hardcoded 48px)
   - Progress bar thickness option
3. **Consider** adding visual feedback when items are grouped (show count in tooltip)

## Other Notes

### Project Structure
```
/Volumes/@Basic/Projekty/ReaMD/
├── Main/ReaMD.lua          # Main entry point
└── Libs/
    ├── teleprompter.lua    # Teleprompter window (v3)
    ├── scenario_engine.lua # Item linking, groups, playback sync
    ├── md_renderer.lua     # Markdown rendering + link UI
    ├── md_parser.lua       # Markdown parsing
    ├── config.lua          # Settings persistence
    ├── utils.lua           # Utilities
    └── json.lua            # JSON encoding/decoding
```

### Teleprompter Settings (hardcoded)
- Font size: 48px (`teleprompter.lua:18`)
- Opacity: 50% (`teleprompter.lua:19`)
- Hold duration: 2 seconds (`teleprompter.lua:30`)
- Progress bar height: 4px (`teleprompter.lua:451`)

### Reaper API Used
- `GetMediaItemInfo_Value(item, "I_GROUPID")` - Get item's group ID
- `GetPlayState()` - Check if playing (1) or recording (5)
- `GetPlayPosition2(0)` - Get current playhead position
- `GetSelectedMediaItem(0, 0)` - Get first selected item
