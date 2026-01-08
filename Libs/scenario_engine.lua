-- scenario_engine.lua
-- Timeline synchronization for ReaMD
-- Syncs markdown fragments to Reaper items/regions for playback-following
-- v2: Item-based linking (items can overlap, regions cannot)

local json = require("json")
local Config = require("config")

local ScenarioEngine = {}

-- ═══════════════════════════════════════════════════════════════════════════
-- CONSTANTS
-- ═══════════════════════════════════════════════════════════════════════════

local EXTSTATE_SECTION = "ReaMD"
local EXTSTATE_KEY_MAPPING = "fragment_mapping"

-- Update throttling (~30fps)
local UPDATE_INTERVAL = 0.033

-- Color categories for fragment highlighting
-- Colors adjusted for visibility on both dark and light backgrounds
ScenarioEngine.COLOR_CATEGORIES = {
    {id = "vo",    name = "VO/Dialog", color = 0x2255AA66, button_color = 0x2255AAFF, label = "V"},  -- Dark Blue
    {id = "music", name = "Music",     color = 0x22884466, button_color = 0x228844FF, label = "M"},  -- Dark Green
    {id = "fx",    name = "FX/SFX",    color = 0xBB552266, button_color = 0xBB5522FF, label = "F"},  -- Dark Orange
    {id = "other", name = "Other",     color = 0x77229966, button_color = 0x772299FF, label = "O"},  -- Dark Purple
}

-- Default category index
local DEFAULT_COLOR_CATEGORY = 1

-- ═══════════════════════════════════════════════════════════════════════════
-- STATE
-- ═══════════════════════════════════════════════════════════════════════════

ScenarioEngine.enabled = false       -- Is scenario mode active?
ScenarioEngine.regions = {}          -- Cache of project regions (legacy)
ScenarioEngine.items = {}            -- Cache of project items
ScenarioEngine.fragment_map = {}     -- Fragment data from ExtState
ScenarioEngine.current_region = -1   -- Currently playing region ID (legacy)
ScenarioEngine.active_fragments = {} -- Currently active fragments (item-based)

-- Internal state
local last_update_time = 0           -- For throttling
local has_sws = nil                  -- Cached SWS extension check

-- ═══════════════════════════════════════════════════════════════════════════
-- HELPER FUNCTIONS
-- ═══════════════════════════════════════════════════════════════════════════

--- Calculate a simple hash of content for change detection
-- @param content string: Content to hash
-- @return string: Hash string
function ScenarioEngine.calculate_hash(content)
    if not content or content == "" then
        return "0"
    end

    local hash = 0
    for i = 1, #content do
        hash = (hash * 31 + content:byte(i)) % 2147483647
    end

    return string.format("%x", hash)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- ITEM MANAGEMENT (v2)
-- ═══════════════════════════════════════════════════════════════════════════

--- Check if SWS extension is available
-- @return boolean: True if SWS is installed
function ScenarioEngine.has_sws()
    if has_sws == nil then
        has_sws = reaper.BR_GetMediaItemByGUID ~= nil
    end
    return has_sws
end

--- Get item GUID string
-- Works with or without SWS extension
-- @param item MediaItem: Reaper item handle
-- @return string|nil: GUID string or nil
function ScenarioEngine.get_item_guid(item)
    if not item then return nil end

    if ScenarioEngine.has_sws() then
        -- SWS: direct function
        return reaper.BR_GetMediaItemGUID(item)
    else
        -- Native: parse from state chunk
        local _, chunk = reaper.GetItemStateChunk(item, "", false)
        if chunk then
            local guid = chunk:match("GUID ({[^}]+})")
            return guid
        end
    end
    return nil
end

--- Find item by GUID
-- @param guid string: Item GUID to find
-- @return MediaItem|nil: Item handle or nil
function ScenarioEngine.get_item_by_guid(guid)
    if not guid then return nil end

    if ScenarioEngine.has_sws() then
        -- SWS: direct lookup
        return reaper.BR_GetMediaItemByGUID(0, guid)
    else
        -- Native: iterate all items
        local num_items = reaper.CountMediaItems(0)
        for i = 0, num_items - 1 do
            local item = reaper.GetMediaItem(0, i)
            if ScenarioEngine.get_item_guid(item) == guid then
                return item
            end
        end
    end
    return nil
end

--- Get item position and length
-- @param item_guid string: Item GUID
-- @return number|nil, number|nil: Start position and end position, or nil if not found
function ScenarioEngine.get_item_bounds(item_guid)
    local item = ScenarioEngine.get_item_by_guid(item_guid)
    if not item then
        return nil, nil
    end

    local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
    local len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
    return pos, pos + len
end

--- Get item at edit cursor position (for linking)
-- @return MediaItem|nil, string|nil: Item handle and GUID, or nil
function ScenarioEngine.get_item_at_cursor()
    local cursor_pos = reaper.GetCursorPosition()
    local num_items = reaper.CountMediaItems(0)

    for i = 0, num_items - 1 do
        local item = reaper.GetMediaItem(0, i)
        local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
        local len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")

        if cursor_pos >= pos and cursor_pos <= pos + len then
            local guid = ScenarioEngine.get_item_guid(item)
            return item, guid
        end
    end
    return nil, nil
end

--- Get all items in the same group as given item
-- @param item MediaItem: Source item
-- @return table: Array of items in the group (including source)
local function get_items_in_group(item)
    local group_id = reaper.GetMediaItemInfo_Value(item, "I_GROUPID")

    -- If not in a group, return just this item
    if group_id == 0 then
        return {item}
    end

    -- Find all items with same group ID
    local group_items = {}
    local num_items = reaper.CountMediaItems(0)

    for i = 0, num_items - 1 do
        local check_item = reaper.GetMediaItem(0, i)
        local check_group = reaper.GetMediaItemInfo_Value(check_item, "I_GROUPID")
        if check_group == group_id then
            table.insert(group_items, check_item)
        end
    end

    return group_items
end

--- Get currently selected item (for linking via [Link] button)
-- If item is in a group, returns all items from that group
-- @return MediaItem|nil, string|nil: First item handle and GUID, or nil
-- @return table|nil: Array of all GUIDs (for group support)
function ScenarioEngine.get_selected_item()
    local item = reaper.GetSelectedMediaItem(0, 0)  -- First selected item
    if not item then
        return nil, nil, nil
    end

    -- Get all items in group (or just this one if not grouped)
    local group_items = get_items_in_group(item)

    -- Collect all GUIDs
    local guids = {}
    for _, grp_item in ipairs(group_items) do
        local guid = ScenarioEngine.get_item_guid(grp_item)
        if guid then
            table.insert(guids, guid)
        end
    end

    local first_guid = ScenarioEngine.get_item_guid(item)
    return item, first_guid, guids
end

--- Get info about selected item for display
-- @return table|nil: {guid, pos, len, track_name} or nil
function ScenarioEngine.get_selected_item_info()
    local item, guid = ScenarioEngine.get_selected_item()
    if not item then
        return nil
    end

    local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
    local len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
    local track = reaper.GetMediaItem_Track(item)
    local track_name = ""
    if track then
        _, track_name = reaper.GetTrackName(track)
    end

    return {
        item = item,
        guid = guid,
        pos = pos,
        len = len,
        endpos = pos + len,
        track_name = track_name
    }
end

--- Refresh items cache from project
-- Caches all items with their positions for quick lookup
function ScenarioEngine.refresh_items()
    ScenarioEngine.items = {}

    local num_items = reaper.CountMediaItems(0)
    for i = 0, num_items - 1 do
        local item = reaper.GetMediaItem(0, i)
        local guid = ScenarioEngine.get_item_guid(item)
        local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
        local len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
        local track = reaper.GetMediaItem_Track(item)
        local track_name = ""
        if track then
            _, track_name = reaper.GetTrackName(track)
        end

        table.insert(ScenarioEngine.items, {
            item = item,
            guid = guid,
            pos = pos,
            len = len,
            endpos = pos + len,
            track = track,
            track_name = track_name,
            index = i
        })
    end

    -- Sort by position
    table.sort(ScenarioEngine.items, function(a, b)
        return a.pos < b.pos
    end)
end

--- Format item for display (with timecode and track)
-- @param item_data table: Item data from cache
-- @return string: Formatted string like "0:32 - Track 1"
function ScenarioEngine.format_item_display(item_data)
    if not item_data then return "(none)" end

    local minutes = math.floor(item_data.pos / 60)
    local seconds = math.floor(item_data.pos % 60)
    local name = item_data.track_name or "Item"
    return string.format("%d:%02d - %s", minutes, seconds, name)
end

--- Get all items that contain the given position
-- @param play_pos number: Position in seconds
-- @return table: Array of item_data tables
function ScenarioEngine.get_items_at_position(play_pos)
    local active_items = {}

    for _, item_data in ipairs(ScenarioEngine.items) do
        if play_pos >= item_data.pos and play_pos <= item_data.endpos then
            table.insert(active_items, item_data)
        end
    end

    return active_items
end

--- Normalize text for fuzzy matching
-- @param text string: Text to normalize
-- @return string: Normalized text (lowercase, no punctuation, single spaces)
local function normalize_for_match(text)
    if not text then return "" end
    return text:lower():gsub("[^%w%s]", ""):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
end

--- Fuzzy match between region name and heading text
-- @param region_name string: Region name from Reaper
-- @param heading_text string: Heading text from markdown
-- @return boolean: True if match found
local function fuzzy_match(region_name, heading_text)
    local a = normalize_for_match(region_name)
    local b = normalize_for_match(heading_text)

    if a == "" or b == "" then
        return false
    end

    -- Exact match or substring match
    return a == b or a:find(b, 1, true) ~= nil or b:find(a, 1, true) ~= nil
end

--- Extract plain text from heading AST node
-- @param heading_node table: Heading AST node with children
-- @return string: Plain text content
local function extract_heading_text(heading_node)
    if not heading_node or not heading_node.children then
        return ""
    end

    local parts = {}
    for _, child in ipairs(heading_node.children) do
        if child.type == "text" then
            table.insert(parts, child.text)
        elseif child.children then
            -- Recursively get text from nested nodes (bold, italic, etc.)
            table.insert(parts, extract_heading_text(child))
        end
    end

    return table.concat(parts, "")
end

-- ═══════════════════════════════════════════════════════════════════════════
-- REGION MANAGEMENT
-- ═══════════════════════════════════════════════════════════════════════════

--- Refresh regions from Reaper project
-- Scans all project markers/regions and caches region data
function ScenarioEngine.refresh_regions()
    ScenarioEngine.regions = {}

    local num_markers, num_regions = reaper.CountProjectMarkers(0)
    local total = num_markers + num_regions

    for i = 0, total - 1 do
        local retval, isrgn, pos, rgnend, name, markrgnindexnumber, color =
            reaper.EnumProjectMarkers3(0, i)

        if retval and isrgn then
            table.insert(ScenarioEngine.regions, {
                idx = i,
                id = markrgnindexnumber,
                pos = pos,
                rgnend = rgnend,
                name = name,
                color = color
            })
        end
    end

    -- Sort by position
    table.sort(ScenarioEngine.regions, function(a, b)
        return a.pos < b.pos
    end)
end

--- Get the region at the current play position
-- @return table|nil: Region data or nil if not playing or no region
function ScenarioEngine.get_current_region()
    -- Check play state (1 = playing, 2 = paused, 4 = recording)
    local play_state = reaper.GetPlayState()
    local is_playing = (play_state == 1) or (play_state == 5)  -- playing or playing+recording
    if not is_playing then
        return nil  -- Not playing
    end

    local play_pos = reaper.GetPlayPosition2(0)
    local marker_idx, region_idx = reaper.GetLastMarkerAndCurRegion(0, play_pos)

    if region_idx < 0 then
        return nil  -- No region at position
    end

    -- Find region data by index
    for _, region in ipairs(ScenarioEngine.regions) do
        if region.id == region_idx then
            return region
        end
    end

    -- Region not in cache - refresh and try again
    ScenarioEngine.refresh_regions()

    -- Try again after refresh
    for _, region in ipairs(ScenarioEngine.regions) do
        if region.id == region_idx then
            return region
        end
    end

    return nil
end

-- ═══════════════════════════════════════════════════════════════════════════
-- FRAGMENT MANAGEMENT
-- ═══════════════════════════════════════════════════════════════════════════

--- Find fragment containing a specific line number
-- @param line number: Line number to find
-- @return table|nil: Fragment data or nil
function ScenarioEngine.find_fragment_for_line(line)
    if not ScenarioEngine.fragment_map.fragments then
        return nil
    end

    for _, fragment in ipairs(ScenarioEngine.fragment_map.fragments) do
        if line >= fragment.line_start and line <= fragment.line_end then
            return fragment
        end
    end

    return nil
end

--- Find fragment linked to a specific region
-- @param region_id number: Region ID to find
-- @return table|nil: Fragment data or nil
function ScenarioEngine.find_fragment_for_region(region_id)
    if not ScenarioEngine.fragment_map.fragments then
        return nil
    end

    for _, fragment in ipairs(ScenarioEngine.fragment_map.fragments) do
        if fragment.region_id == region_id then
            return fragment
        end
    end

    return nil
end

--- Link a fragment to a region
-- @param region_id number: Region ID
-- @param line_start number: Starting line of fragment
-- @param line_end number: Ending line of fragment
-- @param identifier string: Display text (heading or first cell content)
-- @param node_type string: Type of node ("heading" or "table_row")
-- @param row_index number: Optional row index for tables with duplicate names
function ScenarioEngine.link_fragment(region_id, line_start, line_end, identifier, node_type, row_index)
    if not ScenarioEngine.fragment_map.fragments then
        ScenarioEngine.fragment_map.fragments = {}
    end

    node_type = node_type or "heading"

    -- Check if this line is already linked (update if so)
    for i, fragment in ipairs(ScenarioEngine.fragment_map.fragments) do
        if fragment.line_start == line_start then
            ScenarioEngine.fragment_map.fragments[i] = {
                region_id = region_id,
                line_start = line_start,
                line_end = line_end,
                identifier = identifier,
                node_type = node_type,
                row_index = row_index,
                -- Keep backward compatibility
                heading = identifier
            }
            return
        end
    end

    -- Add new link
    table.insert(ScenarioEngine.fragment_map.fragments, {
        region_id = region_id,
        line_start = line_start,
        line_end = line_end,
        identifier = identifier,
        node_type = node_type,
        row_index = row_index,
        heading = identifier
    })

    -- Sort by line_start
    table.sort(ScenarioEngine.fragment_map.fragments, function(a, b)
        return a.line_start < b.line_start
    end)
end

--- Unlink a fragment by line_start (for table rows/headings)
-- @param line_start number: Line start of element to unlink
function ScenarioEngine.unlink_fragment_by_line(line_start)
    if not ScenarioEngine.fragment_map.fragments then
        return
    end

    for i = #ScenarioEngine.fragment_map.fragments, 1, -1 do
        if ScenarioEngine.fragment_map.fragments[i].line_start == line_start then
            table.remove(ScenarioEngine.fragment_map.fragments, i)
            return
        end
    end
end

--- Find fragment by line_start
-- @param line_start number: Line start to find
-- @return table|nil: Fragment data or nil
function ScenarioEngine.find_fragment_by_line(line_start)
    if not ScenarioEngine.fragment_map.fragments then
        return nil
    end

    for _, fragment in ipairs(ScenarioEngine.fragment_map.fragments) do
        if fragment.line_start == line_start then
            return fragment
        end
    end

    return nil
end

--- Get region name by ID
-- @param region_id number: Region ID
-- @return string: Region name or empty string
function ScenarioEngine.get_region_name(region_id)
    for _, region in ipairs(ScenarioEngine.regions) do
        if region.id == region_id then
            return region.name
        end
    end
    return ""
end

--- Format region for display (with timecode)
-- @param region table: Region data
-- @return string: Formatted string like "0:32 - Verse 1"
function ScenarioEngine.format_region_display(region)
    if not region then return "(none)" end

    local minutes = math.floor(region.pos / 60)
    local seconds = math.floor(region.pos % 60)
    return string.format("%d:%02d - %s", minutes, seconds, region.name)
end

--- Unlink a fragment from a region
-- @param region_id number: Region ID to unlink
function ScenarioEngine.unlink_fragment(region_id)
    if not ScenarioEngine.fragment_map.fragments then
        return
    end

    for i = #ScenarioEngine.fragment_map.fragments, 1, -1 do
        if ScenarioEngine.fragment_map.fragments[i].region_id == region_id then
            table.remove(ScenarioEngine.fragment_map.fragments, i)
            return
        end
    end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- ITEM-BASED FRAGMENT LINKING (v2)
-- ═══════════════════════════════════════════════════════════════════════════

--- Link a fragment to an item by GUID (v3: multi-item support)
-- @param item_guid string: Item GUID to add
-- @param line_start number: Starting line of fragment
-- @param line_end number: Ending line of fragment
-- @param identifier string: Display text (heading or first cell content)
-- @param node_type string: Type of node ("heading" or "table_row")
-- @param row_index number: Optional row index for tables with duplicate names
function ScenarioEngine.link_fragment_to_item(item_guid, line_start, line_end, identifier, node_type, row_index)
    if not ScenarioEngine.fragment_map.fragments then
        ScenarioEngine.fragment_map.fragments = {}
    end

    node_type = node_type or "heading"

    -- Check if this line already has a fragment
    for i, fragment in ipairs(ScenarioEngine.fragment_map.fragments) do
        if fragment.line_start == line_start then
            -- Fragment exists - ensure item_guids array exists
            if not fragment.item_guids then
                -- Migrate from old single item_guid
                if fragment.item_guid then
                    fragment.item_guids = {fragment.item_guid}
                    fragment.item_guid = nil  -- Clear old field
                else
                    fragment.item_guids = {}
                end
            end
            -- Add new guid if not already present
            local already_linked = false
            for _, guid in ipairs(fragment.item_guids) do
                if guid == item_guid then
                    already_linked = true
                    break
                end
            end
            if not already_linked then
                table.insert(fragment.item_guids, item_guid)
            end
            return
        end
    end

    -- Add new fragment with item_guids array
    table.insert(ScenarioEngine.fragment_map.fragments, {
        item_guids = {item_guid},
        line_start = line_start,
        line_end = line_end,
        identifier = identifier,
        node_type = node_type,
        row_index = row_index,
        heading = identifier
    })

    -- Sort by line_start
    table.sort(ScenarioEngine.fragment_map.fragments, function(a, b)
        return a.line_start < b.line_start
    end)
end

--- Remove a specific item from a fragment (v3)
-- @param line_start number: Line start of fragment
-- @param item_guid string: Item GUID to remove
-- @return boolean: True if removed
function ScenarioEngine.remove_item_from_fragment(line_start, item_guid)
    if not ScenarioEngine.fragment_map.fragments then
        return false
    end

    for i, fragment in ipairs(ScenarioEngine.fragment_map.fragments) do
        if fragment.line_start == line_start then
            if fragment.item_guids then
                for j = #fragment.item_guids, 1, -1 do
                    if fragment.item_guids[j] == item_guid then
                        table.remove(fragment.item_guids, j)
                        -- If no items left, remove the whole fragment
                        if #fragment.item_guids == 0 then
                            table.remove(ScenarioEngine.fragment_map.fragments, i)
                        end
                        return true
                    end
                end
            end
            break
        end
    end
    return false
end

--- Get all item GUIDs for a fragment (v3)
-- @param line_start number: Line start of fragment
-- @return table: Array of item GUIDs (empty if none)
function ScenarioEngine.get_fragment_item_guids(line_start)
    local fragment = ScenarioEngine.find_fragment_by_line(line_start)
    if not fragment then
        return {}
    end

    -- Handle both old (item_guid) and new (item_guids) format
    if fragment.item_guids then
        return fragment.item_guids
    elseif fragment.item_guid then
        return {fragment.item_guid}
    end
    return {}
end

--- Jump to an item on timeline (select, set edit cursor, time selection for copy)
-- @param item_guid string: Item GUID to jump to
-- @return boolean: True if item found and jumped to
function ScenarioEngine.jump_to_item(item_guid)
    local item = ScenarioEngine.get_item_by_guid(item_guid)
    if not item then
        return false
    end

    -- Get item position and length
    local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
    local len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")

    -- Unselect all items first
    reaper.SelectAllMediaItems(0, false)

    -- Select this item
    reaper.SetMediaItemSelected(item, true)

    -- Move edit cursor to item start and scroll view
    reaper.SetEditCurPos(pos, true, false)

    -- Set time selection around item (for easy copy with Ctrl+C)
    reaper.GetSet_LoopTimeRange(true, false, pos, pos + len, false)

    -- Scroll arrange view to show item
    local track = reaper.GetMediaItem_Track(item)
    if track then
        -- Select track too for context
        reaper.SetOnlyTrackSelected(track)
        reaper.SetMixerScroll(track)
    end

    -- Update arrange view
    reaper.UpdateArrange()

    return true
end

--- Get color category for a fragment
-- @param line_start number: Line start of fragment
-- @return number: Category index (1-based), defaults to 1
function ScenarioEngine.get_fragment_color_category(line_start)
    local fragment = ScenarioEngine.find_fragment_by_line(line_start)
    if fragment and fragment.color_category then
        return fragment.color_category
    end
    return DEFAULT_COLOR_CATEGORY
end

--- Set color category for a fragment
-- @param line_start number: Line start of fragment
-- @param category_index number: Category index (1-based)
-- @return boolean: True if set successfully
function ScenarioEngine.set_fragment_color_category(line_start, category_index)
    if not ScenarioEngine.fragment_map.fragments then
        return false
    end

    -- Validate category index
    if category_index < 1 or category_index > #ScenarioEngine.COLOR_CATEGORIES then
        category_index = DEFAULT_COLOR_CATEGORY
    end

    for _, fragment in ipairs(ScenarioEngine.fragment_map.fragments) do
        if fragment.line_start == line_start then
            fragment.color_category = category_index
            return true
        end
    end
    return false
end

--- Cycle to next color category for a fragment
-- @param line_start number: Line start of fragment
-- @return number: New category index
function ScenarioEngine.cycle_fragment_color_category(line_start)
    local current = ScenarioEngine.get_fragment_color_category(line_start)
    local next_cat = (current % #ScenarioEngine.COLOR_CATEGORIES) + 1
    ScenarioEngine.set_fragment_color_category(line_start, next_cat)
    return next_cat
end

--- Get color category info
-- @param category_index number: Category index (1-based)
-- @return table: Category data {id, name, color, button_color}
function ScenarioEngine.get_color_category_info(category_index)
    if category_index and category_index >= 1 and category_index <= #ScenarioEngine.COLOR_CATEGORIES then
        return ScenarioEngine.COLOR_CATEGORIES[category_index]
    end
    return ScenarioEngine.COLOR_CATEGORIES[DEFAULT_COLOR_CATEGORY]
end

--- Find fragment linked to a specific item
-- @param item_guid string: Item GUID to find
-- @return table|nil: Fragment data or nil
function ScenarioEngine.find_fragment_for_item(item_guid)
    if not ScenarioEngine.fragment_map.fragments then
        return nil
    end

    for _, fragment in ipairs(ScenarioEngine.fragment_map.fragments) do
        if fragment.item_guid == item_guid then
            return fragment
        end
    end

    return nil
end

--- Get all fragments that should be highlighted at current play position
-- Returns multiple fragments if multiple linked items overlap at playhead
-- v3: Supports item_guids array (multiple items per fragment)
-- @return table: Array of fragment tables, empty if not playing or no matches
function ScenarioEngine.get_active_fragments()
    -- Check play state
    local play_state = reaper.GetPlayState()
    local is_playing = (play_state == 1) or (play_state == 5)
    if not is_playing then
        return {}
    end

    local play_pos = reaper.GetPlayPosition2(0)
    local active = {}

    if not ScenarioEngine.fragment_map.fragments then
        return {}
    end

    for _, fragment in ipairs(ScenarioEngine.fragment_map.fragments) do
        local is_active = false

        -- v3: Check item_guids array
        if fragment.item_guids and #fragment.item_guids > 0 then
            for _, guid in ipairs(fragment.item_guids) do
                local start_pos, end_pos = ScenarioEngine.get_item_bounds(guid)
                if start_pos and play_pos >= start_pos and play_pos <= end_pos then
                    is_active = true
                    break  -- At least one item is active
                end
            end
        -- Legacy: single item_guid
        elseif fragment.item_guid then
            local start_pos, end_pos = ScenarioEngine.get_item_bounds(fragment.item_guid)
            if start_pos and play_pos >= start_pos and play_pos <= end_pos then
                is_active = true
            end
        -- Legacy: check region-based linking
        elseif fragment.region_id then
            local region = nil
            for _, r in ipairs(ScenarioEngine.regions) do
                if r.id == fragment.region_id then
                    region = r
                    break
                end
            end
            if region and play_pos >= region.pos and play_pos <= region.rgnend then
                is_active = true
            end
        end

        if is_active then
            table.insert(active, fragment)
        end
    end

    return active
end

--- Get item info for display in UI
-- @param item_guid string: Item GUID
-- @return table|nil: Item data table or nil
function ScenarioEngine.get_item_info(item_guid)
    if not item_guid then return nil end

    -- Check cache first
    for _, item_data in ipairs(ScenarioEngine.items) do
        if item_data.guid == item_guid then
            return item_data
        end
    end

    -- Not in cache, try to find directly
    local item = ScenarioEngine.get_item_by_guid(item_guid)
    if item then
        local pos = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
        local len = reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
        local track = reaper.GetMediaItem_Track(item)
        local track_name = ""
        if track then
            _, track_name = reaper.GetTrackName(track)
        end
        return {
            item = item,
            guid = item_guid,
            pos = pos,
            len = len,
            endpos = pos + len,
            track = track,
            track_name = track_name
        }
    end

    return nil
end

--- Auto-link regions to headings by fuzzy name matching
-- @param parsed_ast table: Parsed markdown AST from md_parser
-- @return number: Count of links created
function ScenarioEngine.auto_link_by_name(parsed_ast)
    if not parsed_ast or not parsed_ast.children then
        return 0
    end

    -- Refresh regions first
    ScenarioEngine.refresh_regions()

    local links_created = 0

    -- Find all headings in AST
    local headings = {}
    for _, node in ipairs(parsed_ast.children) do
        if node.type == "heading" then
            local text = extract_heading_text(node)
            table.insert(headings, {
                text = text,
                line_start = node.line_start,
                line_end = node.line_end
            })
        end
    end

    -- Calculate heading regions (line_start to next heading or end)
    for i, heading in ipairs(headings) do
        if i < #headings then
            -- End at start of next heading - 1
            heading.section_end = headings[i + 1].line_start - 1
        else
            -- Last heading extends to end of document
            heading.section_end = parsed_ast.line_end or heading.line_end
        end
    end

    -- Match regions to headings
    for _, region in ipairs(ScenarioEngine.regions) do
        for _, heading in ipairs(headings) do
            if fuzzy_match(region.name, heading.text) then
                -- Check if already linked
                local existing = ScenarioEngine.find_fragment_for_region(region.id)
                if not existing then
                    ScenarioEngine.link_fragment(
                        region.id,
                        heading.line_start,
                        heading.section_end,
                        heading.text
                    )
                    links_created = links_created + 1
                end
                break  -- Move to next region
            end
        end
    end

    return links_created
end

-- ═══════════════════════════════════════════════════════════════════════════
-- PERSISTENCE
-- ═══════════════════════════════════════════════════════════════════════════

-- File extension for scenario data (separate file)
local REAMD_EXT = ".reamd"

-- Legacy marker (for backward compatibility / cleanup)
local REAMD_MARKER_START = "<!-- reamd-scenario:"
local REAMD_MARKER_END = ":reamd -->"

--- Save mapping to Project ExtState (for session persistence)
-- @param file_path string: Path to markdown file
-- @param content_hash string: Hash of file content
function ScenarioEngine.save_mapping(file_path, content_hash)
    ScenarioEngine.fragment_map.markdown_file = file_path
    ScenarioEngine.fragment_map.file_hash = content_hash

    local json_str = json.encode(ScenarioEngine.fragment_map)
    reaper.SetProjExtState(0, EXTSTATE_SECTION, EXTSTATE_KEY_MAPPING, json_str)
end

--- Load mapping from Project ExtState
-- @param file_path string: Expected markdown file path
-- @return boolean: True if loaded successfully and file matches
function ScenarioEngine.load_mapping(file_path)
    local retval, json_str = reaper.GetProjExtState(0, EXTSTATE_SECTION, EXTSTATE_KEY_MAPPING)

    if retval == 0 or not json_str or json_str == "" then
        ScenarioEngine.fragment_map = { fragments = {} }
        return false
    end

    local success, data = pcall(json.decode, json_str)
    if not success or not data then
        ScenarioEngine.fragment_map = { fragments = {} }
        return false
    end

    -- Validate file matches
    if data.markdown_file ~= file_path then
        ScenarioEngine.fragment_map = { fragments = {} }
        return false
    end

    -- Ensure fragments array exists
    if not data.fragments then
        data.fragments = {}
    end

    ScenarioEngine.fragment_map = data
    return true
end

--- Save mapping to a separate .reamd file (permanent storage)
-- Creates file_path.reamd alongside the markdown file
-- @param file_path string: Path to markdown file
-- @return boolean: True if saved successfully
function ScenarioEngine.save_to_file(file_path)
    if not file_path then return false end
    if not ScenarioEngine.fragment_map.fragments or #ScenarioEngine.fragment_map.fragments == 0 then
        return false  -- Nothing to save
    end

    -- Prepare data to save
    -- Version 3: supports item_guids array (multiple items per fragment)
    local save_data = {
        version = 3,
        markdown_file = file_path,
        fragments = {}
    }
    for _, frag in ipairs(ScenarioEngine.fragment_map.fragments) do
        -- Get item_guids array (handle both old and new format)
        local guids = frag.item_guids
        if not guids and frag.item_guid then
            guids = {frag.item_guid}
        end

        table.insert(save_data.fragments, {
            item_guids = guids,              -- v3: multi-item support
            region_id = frag.region_id,      -- v1: region-based (legacy)
            line_start = frag.line_start,
            line_end = frag.line_end,
            identifier = frag.identifier,
            node_type = frag.node_type,
            row_index = frag.row_index,
            color_category = frag.color_category  -- v3.1: color category
        })
    end

    -- Write to .reamd file
    local reamd_path = file_path .. REAMD_EXT
    local json_str = json.encode(save_data)

    local f = io.open(reamd_path, "w")
    if not f then return false end
    f:write(json_str)
    f:close()

    return true
end

--- Load mapping from .reamd file
-- Reads the separate scenario file alongside markdown
-- v3: Migrates old item_guid to item_guids array
-- @param file_path string: Path to markdown file
-- @return boolean: True if mapping found and loaded
function ScenarioEngine.load_from_file(file_path)
    if not file_path then return false end

    local reamd_path = file_path .. REAMD_EXT

    -- Read .reamd file
    local f = io.open(reamd_path, "r")
    if not f then
        -- Try legacy: check for embedded marker in MD file
        return ScenarioEngine.load_from_file_legacy(file_path)
    end
    local json_str = f:read("*all")
    f:close()

    -- Parse JSON
    local success, data = pcall(json.decode, json_str)
    if not success or not data or not data.fragments then
        return false
    end

    -- Migrate fragments from v2 (item_guid) to v3 (item_guids)
    for _, frag in ipairs(data.fragments) do
        if frag.item_guid and not frag.item_guids then
            frag.item_guids = {frag.item_guid}
            frag.item_guid = nil
        end
    end

    -- Load into fragment_map
    ScenarioEngine.fragment_map = {
        markdown_file = file_path,
        fragments = data.fragments
    }

    return true
end

--- Load mapping from legacy embedded marker (backward compatibility)
-- @param file_path string: Path to markdown file
-- @return boolean: True if mapping found and loaded
function ScenarioEngine.load_from_file_legacy(file_path)
    if not file_path then return false end

    local f = io.open(file_path, "r")
    if not f then return false end
    local content = f:read("*all")
    f:close()

    -- Find legacy reamd marker
    local start_pos = content:find(REAMD_MARKER_START, 1, true)
    if not start_pos then
        return false
    end

    local end_pos = content:find(REAMD_MARKER_END, start_pos, true)
    if not end_pos then
        return false
    end

    -- Extract JSON
    local json_start = start_pos + #REAMD_MARKER_START
    local json_str = content:sub(json_start, end_pos - 1)

    -- Parse JSON
    local success, data = pcall(json.decode, json_str)
    if not success or not data or not data.fragments then
        return false
    end

    -- Load into fragment_map
    ScenarioEngine.fragment_map = {
        markdown_file = file_path,
        fragments = data.fragments
    }

    return true
end

--- Check if a markdown file has scenario data (in .reamd file or legacy embedded)
-- @param file_path string: Path to markdown file
-- @return boolean: True if scenario data exists
function ScenarioEngine.file_has_scenario_data(file_path)
    if not file_path then return false end

    -- Check for .reamd file first
    local reamd_path = file_path .. REAMD_EXT
    local f = io.open(reamd_path, "r")
    if f then
        f:close()
        return true
    end

    -- Check for legacy embedded marker
    f = io.open(file_path, "r")
    if not f then return false end
    local content = f:read("*all")
    f:close()

    return content:find(REAMD_MARKER_START, 1, true) ~= nil
end

--- Get markdown content without the reamd marker (for parsing)
-- @param content string: Full file content
-- @return string: Content without reamd marker
function ScenarioEngine.strip_reamd_marker(content)
    if not content then return "" end
    local marker_pattern = "\n?\n?" .. REAMD_MARKER_START .. ".-" .. REAMD_MARKER_END
    return content:gsub(marker_pattern, "")
end

--- Remove legacy embedded marker from markdown file
-- Call this to clean up old files after migrating to .reamd format
-- @param file_path string: Path to markdown file
-- @return boolean: True if marker was found and removed
function ScenarioEngine.remove_legacy_marker(file_path)
    if not file_path then return false end

    local f = io.open(file_path, "r")
    if not f then return false end
    local content = f:read("*all")
    f:close()

    -- Check if marker exists
    if not content:find(REAMD_MARKER_START, 1, true) then
        return false  -- No marker to remove
    end

    -- Remove marker
    local clean_content = ScenarioEngine.strip_reamd_marker(content)

    -- Write back
    f = io.open(file_path, "w")
    if not f then return false end
    f:write(clean_content)
    f:close()

    return true
end

-- ═══════════════════════════════════════════════════════════════════════════
-- UPDATE LOOP
-- ═══════════════════════════════════════════════════════════════════════════

--- Initialize scenario engine
-- Loads mapping from project and refreshes regions/items
function ScenarioEngine.init()
    ScenarioEngine.refresh_regions()
    ScenarioEngine.refresh_items()
    ScenarioEngine.current_region = -1
    ScenarioEngine.active_fragments = {}
    last_update_time = 0
end

--- Update function (v2) - supports multiple active fragments from items
-- @return boolean: True if active fragments changed
-- @return table: Array of active fragments (can be multiple for overlapping items)
-- @return boolean: True if auto_scroll is enabled
function ScenarioEngine.update()
    -- Throttle updates
    local current_time = reaper.time_precise()
    if current_time - last_update_time < UPDATE_INTERVAL then
        return false, ScenarioEngine.active_fragments, false
    end
    last_update_time = current_time

    -- Get all active fragments (item-based, supports overlapping)
    local new_active = ScenarioEngine.get_active_fragments()

    -- Check if active fragments changed
    local changed = false

    -- Simple comparison: check if count differs or any fragment differs
    if #new_active ~= #ScenarioEngine.active_fragments then
        changed = true
    else
        for i, frag in ipairs(new_active) do
            local old_frag = ScenarioEngine.active_fragments[i]
            if not old_frag or frag.line_start ~= old_frag.line_start then
                changed = true
                break
            end
        end
    end

    -- Update cached active fragments
    ScenarioEngine.active_fragments = new_active

    -- Return change status, active fragments, and auto_scroll setting
    return changed, new_active, changed and Config.get("auto_scroll") or false
end

--- Legacy update function for backward compatibility
-- Returns single fragment (first active one)
-- @return boolean: True if changed
-- @return table|nil: First active fragment or nil
-- @return boolean: True if auto_scroll enabled
function ScenarioEngine.update_legacy()
    local changed, fragments, should_scroll = ScenarioEngine.update()
    local fragment = fragments[1]  -- Get first fragment if any
    return changed, fragment, should_scroll
end

-- ═══════════════════════════════════════════════════════════════════════════
-- NAVIGATION
-- ═══════════════════════════════════════════════════════════════════════════

--- Get scroll target line for a fragment
-- @param fragment table: Fragment data
-- @return number: Line number to scroll to
function ScenarioEngine.get_scroll_target(fragment)
    if not fragment then
        return 1
    end
    return fragment.line_start
end

--- Jump edit cursor to a region's start position
-- @param region_id number: Region ID to jump to
function ScenarioEngine.jump_to_region(region_id)
    -- Find region data
    for _, region in ipairs(ScenarioEngine.regions) do
        if region.id == region_id then
            -- Set edit cursor position
            -- moveview=true, seekplay=false
            reaper.SetEditCurPos(region.pos, true, false)
            return
        end
    end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- CHECKPOINT: scenario_engine.lua COMPLETE
-- Exported:
--   ScenarioEngine.init() - Initialize and load mapping
--   ScenarioEngine.refresh_regions() - Scan project regions
--   ScenarioEngine.update() - Frame update, returns (changed, fragment)
--   ScenarioEngine.get_current_region() - Current region at play position
--   ScenarioEngine.find_fragment_for_line(line) - Fragment at line
--   ScenarioEngine.find_fragment_for_region(region_id) - Fragment for region
--   ScenarioEngine.find_fragment_by_line(line_start) - Fragment by line start
--   ScenarioEngine.link_fragment(region_id, line_start, line_end, identifier, node_type, row_index)
--   ScenarioEngine.unlink_fragment(region_id) - Unlink by region ID
--   ScenarioEngine.unlink_fragment_by_line(line_start) - Unlink by line
--   ScenarioEngine.get_region_name(region_id) - Get region name by ID
--   ScenarioEngine.format_region_display(region) - Format "0:32 - Name"
--   ScenarioEngine.auto_link_by_name(ast) - Match regions to headings
--   ScenarioEngine.save_mapping(file_path, hash)
--   ScenarioEngine.load_mapping(file_path) -> bool
--   ScenarioEngine.jump_to_region(region_id)
--
-- Fragment structure (v2):
--   {region_id, line_start, line_end, identifier, node_type, row_index, heading}
--   node_type: "heading" | "table_row"
-- ═══════════════════════════════════════════════════════════════════════════

return ScenarioEngine
