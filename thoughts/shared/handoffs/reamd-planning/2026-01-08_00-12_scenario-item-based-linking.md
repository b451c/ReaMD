---
date: 2026-01-08T00:12:37+01:00
session_name: reamd-planning
researcher: Claude
git_commit: N/A (not a git repo)
branch: N/A
repository: ReaMD
topic: "Scenario Mode - Item-Based Linking Implementation"
tags: [implementation, scenario-mode, reaimgui, reaper-items]
status: handoff
last_updated: 2026-01-08
last_updated_by: Claude
type: implementation_strategy
root_span_id:
turn_span_id:
---

# Handoff: Scenario Mode - Switch from Regions to Items

## Task(s)

| Task | Status |
|------|--------|
| Fix highlight not working for table rows | COMPLETED |
| Fix region cache staleness bug | COMPLETED |
| Change scenario save to .reamd file (not embedded in MD) | COMPLETED |
| Remove debug messages | IN PROGRESS (partially done) |
| **Redesign: Item-based linking instead of regions** | PLANNED |

## Critical References

1. `thoughts/ledgers/CONTINUITY_CLAUDE-reamd-planning.md` - Main continuity ledger
2. `Libs/scenario_engine.lua` - Core scenario logic (needs redesign)
3. `Libs/md_renderer.lua` - Table row highlighting (working)

## Recent changes

- `Libs/scenario_engine.lua:103-136` - Added debug to refresh_regions, auto-refresh on cache miss
- `Libs/scenario_engine.lua:140-176` - Added debug to get_current_region
- `Libs/scenario_engine.lua:182-207` - Added debug to find_fragment_for_region
- `Libs/scenario_engine.lua:478-515` - Changed save_to_file to use .reamd file
- `Libs/scenario_engine.lua:517-589` - Changed load_from_file to use .reamd file + legacy fallback
- `Libs/scenario_engine.lua:623-650` - Added remove_legacy_marker function
- `Libs/md_renderer.lua:737-756` - Added table row highlighting with TableSetBgColor
- `Main/ReaMD.lua:562-576` - Added "Clean MD" button to remove legacy marker

## Learnings

### ReaImGui v0.10+ API
- `CreateFont(family)` without size - size goes to `PushFont(ctx, font, size)`
- `BeginChild(ctx, id, w, h, child_flags, window_flags)` - changed signature
- `TableSetBgColor(ctx, TableBgTarget_RowBg0(), 0xRRGGBBAA)` - for row highlighting
- Color format is **0xRRGGBBAA** (not ABGR)

### Reaper Region API Issues
- `GetLastMarkerAndCurRegion` returns only ONE region (highest index when overlapping)
- Region IDs can become stale after adding/deleting regions
- Must refresh region cache when region not found
- `EnumProjectMarkers3` returns `markrgnindexnumber` which is the actual region ID

### Key Bug Found
Region cache was not refreshing when regions were added/deleted in project. Fixed by auto-refreshing when a region ID is not found in cache.

## Post-Mortem

### What Worked
- Debug output approach: Adding ShowConsoleMsg at each step quickly identified where the chain broke
- TableSetBgColor for row highlighting works correctly
- Separate .reamd file approach is cleaner than embedding JSON in markdown

### What Failed
- Tried: Using embedded HTML comment in MD file → Failed because: Breaks markdown rendering
- Error: "Region X not in cache" → Fixed by: Auto-refresh regions when not found
- Initial highlight didn't work → Root cause: Region ID mismatch after project changes

### Key Decisions
- Decision: Use separate .reamd file for scenario data
  - Alternatives: Embedded HTML comment, ExtState only
  - Reason: Clean markdown, portable between projects, human-readable JSON

- Decision: Redesign to use Items instead of Regions
  - Alternatives: Keep regions, support multiple overlapping regions
  - Reason: Items are visual, can overlap naturally, move = auto-update

## Artifacts

- `Libs/scenario_engine.lua` - Contains debug code that needs cleanup
- `Libs/md_renderer.lua` - Contains debug code that needs cleanup
- `Main/ReaMD.lua` - Main script, debug code partially removed
- `thoughts/ledgers/CONTINUITY_CLAUDE-reamd-planning.md` - Ledger to update

## Action Items & Next Steps

### 1. Remove Debug Messages (QUICK)
Remove all `reaper.ShowConsoleMsg` debug calls from:
- `Libs/scenario_engine.lua` (refresh_regions, get_current_region, find_fragment_for_region, load_mapping)
- `Libs/md_renderer.lua` (render_table row debug)
- `Main/ReaMD.lua` (already partially done)

### 2. Redesign Scenario Engine for Items (MAJOR)

**New Architecture:**
```
Instead of: Fragment → Region ID → Region position
New:        Fragment → Item GUID → Item position (dynamic)
```

**Key Changes Needed:**

1. **New linking UI**: Instead of dropdown with regions, show:
   - Track selector
   - "Link to item at cursor" or drag-drop

2. **Item-based storage**:
   ```lua
   fragment = {
       item_guid = "...",  -- Reaper item GUID (stable)
       track_guid = "...", -- For finding the item
       line_start = 18,
       identifier = "Muzyka"
   }
   ```

3. **Dynamic position reading**:
   ```lua
   function get_item_position(item_guid)
       local item = reaper.BR_GetMediaItemByGUID(0, item_guid)
       if item then
           local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
           local len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
           return pos, pos + len
       end
       return nil, nil
   end
   ```

4. **Multiple items active**: Loop through ALL linked items, check if playhead is within each:
   ```lua
   local active_fragments = {}
   for _, frag in ipairs(fragments) do
       local start_pos, end_pos = get_item_position(frag.item_guid)
       if start_pos and play_pos >= start_pos and play_pos <= end_pos then
           table.insert(active_fragments, frag)
       end
   end
   -- Highlight ALL active_fragments
   ```

5. **Handle deleted items**: If item GUID not found, show warning or auto-unlink

### 3. UI for Item Linking (AFTER engine redesign)
- Add "Link to Item" mode
- Click item on timeline → links to selected markdown row
- Visual feedback: item color changes when linked?

## Other Notes

### Reaper Item API (for next session)
```lua
-- Get item by GUID (needs SWS extension for BR_GetMediaItemByGUID)
local item = reaper.BR_GetMediaItemByGUID(0, guid)

-- Get item info
local position = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
local length = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")

-- Get item GUID
local guid = reaper.BR_GetMediaItemGUID(item)

-- Alternative without SWS: iterate all items
local num_items = reaper.CountMediaItems(0)
for i = 0, num_items - 1 do
    local item = reaper.GetMediaItem(0, i)
    -- Check item properties
end
```

### Current File Structure
```
ReaMD/
├── Main/
│   └── ReaMD.lua          # Main script entry point
└── Libs/
    ├── md_parser.lua      # Markdown → AST
    ├── md_renderer.lua    # AST → ImGui (has highlight code)
    ├── scenario_engine.lua # Scenario logic (needs redesign)
    ├── config.lua         # Settings
    ├── utils.lua          # File utilities
    └── json.lua           # JSON library
```

### Test Workflow
1. Open Reaper
2. Actions → Run: ReaMD
3. Click "Open" → select .md file
4. Toggle "Scenario: ON"
5. Link rows to regions/items via dropdown
6. Press Play → rows should highlight as playhead enters linked areas
