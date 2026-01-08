-- teleprompter.lua
-- Transparent overlay window for displaying current scenario text
-- Syncs with Reaper playhead for live script reading

local Teleprompter = {}

-- ═══════════════════════════════════════════════════════════════════════════
-- STATE
-- ═══════════════════════════════════════════════════════════════════════════

Teleprompter.enabled = false
Teleprompter.ctx = nil
Teleprompter.fonts = nil

-- Position and size (will be loaded from config)
local position = {x = 100, y = 100}
local size = {w = 600, h = 150}
local font_size = 48
local bg_opacity = 0.5

-- Track if position was changed by user
local position_dirty = false
local last_pos = {x = 0, y = 0}
local last_size = {w = 0, h = 0}

-- Hold last VO content to prevent flashing between VO fragments
local hold_state = {
    last_vo_fragments = nil,   -- Last displayed VO fragments only
    last_vo_time = 0,          -- When VO was last active
    hold_duration = 2.0,       -- Hold for 2 seconds after VO ends
}

-- Progress bar state for countdown
local progress_state = {
    start_time = nil,          -- When countdown started (time to next VO)
    max_duration = 10,         -- Max bar duration (seconds)
}

-- Category priority (lower = higher priority)
local CATEGORY_PRIORITY = {
    [1] = 1,  -- VO - highest priority
    [2] = 3,  -- Music
    [3] = 2,  -- FX
    [4] = 4,  -- Other - lowest
}

-- ═══════════════════════════════════════════════════════════════════════════
-- HELPERS
-- ═══════════════════════════════════════════════════════════════════════════

--- Sort fragments by priority (VO first)
-- @param fragments table: Array of fragments
-- @return table: Sorted array (VO first, then FX, Music, Other)
local function sort_by_priority(fragments)
    if not fragments or #fragments == 0 then
        return {}
    end

    local sorted = {}
    for _, f in ipairs(fragments) do
        table.insert(sorted, f)
    end

    table.sort(sorted, function(a, b)
        local prio_a = CATEGORY_PRIORITY[a.color_category or 1] or 99
        local prio_b = CATEGORY_PRIORITY[b.color_category or 1] or 99
        return prio_a < prio_b
    end)

    return sorted
end

--- Find time to next VO fragment or end of current VO (treats grouped items as one)
-- @param scenario_engine table: ScenarioEngine module
-- @param vo_fragments table: Currently active VO fragments
-- @return number|nil: Seconds until next VO or end of current, or nil if none
-- @return boolean: true if counting to end of current (not next)
local function get_time_to_next_vo(scenario_engine, vo_fragments)
    local play_state = reaper.GetPlayState()
    local is_playing = (play_state == 1) or (play_state == 5)
    if not is_playing then
        return nil, false
    end

    local play_pos = reaper.GetPlayPosition2(0)
    local next_start = nil

    -- Get all fragments from scenario engine
    local fragment_map = scenario_engine.fragment_map
    if not fragment_map or not fragment_map.fragments then
        return nil, false
    end

    for _, fragment in ipairs(fragment_map.fragments) do
        -- Only check VO fragments (category 1 or nil)
        local cat = tonumber(fragment.color_category) or 1
        if cat == 1 or cat == 0 then
            -- Find earliest start time for this fragment (all items as one unit)
            local fragment_start = nil

            if fragment.item_guids and #fragment.item_guids > 0 then
                -- Multiple items - find earliest start (they're grouped as one)
                for _, guid in ipairs(fragment.item_guids) do
                    local start_pos = scenario_engine.get_item_bounds(guid)
                    if start_pos then
                        if not fragment_start or start_pos < fragment_start then
                            fragment_start = start_pos
                        end
                    end
                end
            elseif fragment.item_guid then
                fragment_start = scenario_engine.get_item_bounds(fragment.item_guid)
            end

            -- Check if this fragment's start is after playhead
            if fragment_start and fragment_start > play_pos then
                if not next_start or fragment_start < next_start then
                    next_start = fragment_start
                end
            end
        end
    end

    if next_start then
        return next_start - play_pos, false
    end

    -- No next VO - check if we have current VO and count to its end
    if vo_fragments and #vo_fragments > 0 then
        local current_frag = vo_fragments[1]
        local fragment_end = nil

        -- Find latest end time (for grouped items)
        if current_frag.item_guids and #current_frag.item_guids > 0 then
            for _, guid in ipairs(current_frag.item_guids) do
                local start_pos, end_pos = scenario_engine.get_item_bounds(guid)
                if end_pos then
                    if not fragment_end or end_pos > fragment_end then
                        fragment_end = end_pos
                    end
                end
            end
        elseif current_frag.item_guid then
            local _, end_pos = scenario_engine.get_item_bounds(current_frag.item_guid)
            fragment_end = end_pos
        end

        if fragment_end and fragment_end > play_pos then
            return fragment_end - play_pos, true
        end
    end

    return nil, false
end

--- Extract text from markdown lines for a fragment
-- @param markdown_lines table: Array of source lines
-- @param line_start number: Start line (1-based)
-- @param line_end number: End line (1-based)
-- @return string: Combined text
local function extract_fragment_text(markdown_lines, line_start, line_end)
    if not markdown_lines or not line_start then
        return ""
    end

    local lines = {}
    local start_idx = math.max(1, line_start)
    local end_idx = math.min(#markdown_lines, line_end or line_start)

    for i = start_idx, end_idx do
        local line = markdown_lines[i]
        if line then
            -- Strip markdown formatting for cleaner display
            line = line:gsub("^#+%s*", "")     -- Remove heading markers
            line = line:gsub("^|.-|%s*", "")   -- Remove table pipes (first column)
            line = line:gsub("|", " ")          -- Replace remaining pipes
            line = line:gsub("%*%*(.-)%*%*", "%1")  -- Remove bold markers
            line = line:gsub("%*(.-)%*", "%1")      -- Remove italic markers
            line = line:gsub("_(.-)_", "%1")        -- Remove underline italic
            line = line:gsub("`(.-)`", "%1")        -- Remove inline code
            line = line:gsub("^%s+", "")            -- Trim leading whitespace
            line = line:gsub("%s+$", "")            -- Trim trailing whitespace

            if #line > 0 then
                table.insert(lines, line)
            end
        end
    end

    return table.concat(lines, " ")
end

-- ═══════════════════════════════════════════════════════════════════════════
-- CONFIG PERSISTENCE
-- ═══════════════════════════════════════════════════════════════════════════

local SECTION = "ReaMD_Teleprompter"

--- Load position and settings from Reaper ExtState
function Teleprompter.load_config()
    local x = tonumber(reaper.GetExtState(SECTION, "x"))
    local y = tonumber(reaper.GetExtState(SECTION, "y"))
    local w = tonumber(reaper.GetExtState(SECTION, "w"))
    local h = tonumber(reaper.GetExtState(SECTION, "h"))
    local fs = tonumber(reaper.GetExtState(SECTION, "font_size"))
    local op = tonumber(reaper.GetExtState(SECTION, "opacity"))

    if x and y then
        position.x = x
        position.y = y
    end
    if w and h then
        size.w = w
        size.h = h
    end
    -- Font size and opacity now fixed in code, not loaded from config
end

--- Save position and settings to Reaper ExtState
function Teleprompter.save_config()
    reaper.SetExtState(SECTION, "x", tostring(math.floor(position.x)), true)
    reaper.SetExtState(SECTION, "y", tostring(math.floor(position.y)), true)
    reaper.SetExtState(SECTION, "w", tostring(math.floor(size.w)), true)
    reaper.SetExtState(SECTION, "h", tostring(math.floor(size.h)), true)
    reaper.SetExtState(SECTION, "font_size", tostring(font_size), true)
    reaper.SetExtState(SECTION, "opacity", tostring(bg_opacity), true)
end

-- ═══════════════════════════════════════════════════════════════════════════
-- PUBLIC API
-- ═══════════════════════════════════════════════════════════════════════════

--- Initialize teleprompter
-- @param ctx ReaImGui context
-- @param fonts table: Font table from main app
function Teleprompter.init(ctx, fonts)
    Teleprompter.ctx = ctx
    Teleprompter.fonts = fonts
    Teleprompter.load_config()
end

--- Toggle teleprompter visibility
function Teleprompter.toggle()
    Teleprompter.enabled = not Teleprompter.enabled
    return Teleprompter.enabled
end

--- Check if teleprompter is enabled
function Teleprompter.is_enabled()
    return Teleprompter.enabled
end

--- Render teleprompter window
-- @param ctx ReaImGui context
-- @param fragments table: Array of active fragments from ScenarioEngine
-- @param markdown_lines table: Source markdown split into lines
-- @param scenario_engine table: ScenarioEngine module for color info
function Teleprompter.render(ctx, fragments, markdown_lines, scenario_engine)
    if not Teleprompter.enabled then
        return
    end

    -- Window flags: no title bar, no scrollbar, no docking
    -- NO AlwaysAutoResize - user controls the size
    local window_flags = reaper.ImGui_WindowFlags_NoTitleBar()
                       + reaper.ImGui_WindowFlags_NoScrollbar()
                       + reaper.ImGui_WindowFlags_NoDocking()
                       + reaper.ImGui_WindowFlags_NoCollapse()

    -- Set position (only on first use or if never set)
    reaper.ImGui_SetNextWindowPos(ctx, position.x, position.y,
        reaper.ImGui_Cond_FirstUseEver())

    -- Set size (only on first use - then user can resize freely)
    reaper.ImGui_SetNextWindowSize(ctx, size.w, size.h,
        reaper.ImGui_Cond_FirstUseEver())

    -- Set size constraints (min/max) - large max for multi-monitor setups
    reaper.ImGui_SetNextWindowSizeConstraints(ctx, 150, 40, 4000, 2000)

    -- Set background transparency
    reaper.ImGui_SetNextWindowBgAlpha(ctx, bg_opacity)

    -- Dark background color for readability, no border
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_WindowBg(), 0x1A1A1AFF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Border(), 0x00000000)
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_WindowBorderSize(), 0)

    local visible, open = reaper.ImGui_Begin(ctx, "ReaMD Teleprompter", true, window_flags)

    if visible then
        -- Track position changes for saving
        local cur_x, cur_y = reaper.ImGui_GetWindowPos(ctx)
        if cur_x ~= last_pos.x or cur_y ~= last_pos.y then
            position.x = cur_x
            position.y = cur_y
            position_dirty = true
            last_pos.x = cur_x
            last_pos.y = cur_y
        end

        -- Track size changes for saving
        local cur_w, cur_h = reaper.ImGui_GetWindowSize(ctx)
        if cur_w ~= last_size.w or cur_h ~= last_size.h then
            size.w = cur_w
            size.h = cur_h
            position_dirty = true
            last_size.w = cur_w
            last_size.h = cur_h
        end

        -- Sort fragments by priority
        local sorted = sort_by_priority(fragments)
        local current_time = reaper.time_precise()

        -- Separate VO fragments from others (FX/Music/Other)
        local vo_fragments = {}
        local other_fragments = {}

        for _, frag in ipairs(sorted) do
            -- VO is category 1, or nil/0 (default) - show as main text
            local cat = tonumber(frag.color_category) or 1
            if cat == 1 or cat == 0 then
                table.insert(vo_fragments, frag)
            else
                table.insert(other_fragments, frag)
            end
        end

        -- Hold logic: only for VO fragments
        if #vo_fragments > 0 then
            -- Update hold state with current VO fragments
            hold_state.last_vo_fragments = {}
            for i, frag in ipairs(vo_fragments) do
                hold_state.last_vo_fragments[i] = frag
            end
            hold_state.last_vo_time = current_time
        elseif hold_state.last_vo_fragments and #hold_state.last_vo_fragments > 0 then
            local elapsed = current_time - hold_state.last_vo_time
            if elapsed < hold_state.hold_duration then
                -- Use held VO fragments during gap
                vo_fragments = hold_state.last_vo_fragments
            end
        end

        if #vo_fragments > 0 or #other_fragments > 0 then
            -- Calculate content height for vertical centering
            local win_h = reaper.ImGui_GetWindowHeight(ctx)
            local content_h = 0
            local vo_text = ""

            -- Estimate VO text height
            if #vo_fragments > 0 then
                local main_frag = vo_fragments[1]
                vo_text = extract_fragment_text(markdown_lines, main_frag.line_start, main_frag.line_end)
                if #vo_text > 0 then
                    content_h = font_size + 10  -- Text height + margin
                end
            end

            -- Add height for indicators
            if #other_fragments > 0 then
                content_h = content_h + 20  -- Indicator line height
            end

            -- Set vertical offset to center content
            local vertical_offset = math.max(0, (win_h - content_h) / 2 - 10)
            reaper.ImGui_SetCursorPosY(ctx, vertical_offset)

            -- Render main VO text (if any)
            if #vo_fragments > 0 and #vo_text > 0 then
                -- Use large font if available
                local fonts = Teleprompter.fonts
                if fonts and fonts.normal then
                    reaper.ImGui_PushFont(ctx, fonts.normal, font_size)
                end

                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), 0xFFFFFFFF)

                -- Calculate text width for horizontal centering
                local text_w = reaper.ImGui_CalcTextSize(ctx, vo_text)
                local avail_w = reaper.ImGui_GetContentRegionAvail(ctx)

                if text_w < avail_w then
                    -- Center short text
                    local offset = (avail_w - text_w) / 2
                    reaper.ImGui_SetCursorPosX(ctx, reaper.ImGui_GetCursorPosX(ctx) + offset)
                    reaper.ImGui_Text(ctx, vo_text)
                else
                    -- Wrap long text
                    reaper.ImGui_PushTextWrapPos(ctx, 0)
                    reaper.ImGui_TextWrapped(ctx, vo_text)
                    reaper.ImGui_PopTextWrapPos(ctx)
                end

                reaper.ImGui_PopStyleColor(ctx)

                if fonts and fonts.normal then
                    reaper.ImGui_PopFont(ctx)
                end
            end

            -- Render FX/Music/Other as small indicators at bottom
            if #other_fragments > 0 then
                if #vo_fragments > 0 then
                    reaper.ImGui_Spacing(ctx)
                end

                local first = true
                for _, frag in ipairs(other_fragments) do
                    local cat = scenario_engine.get_color_category_info(frag.color_category)

                    if not first then
                        reaper.ImGui_SameLine(ctx, 0, 15)
                    end
                    first = false

                    -- Small colored indicator
                    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), cat.button_color)
                    local indicator_text = cat.label .. ": " .. (frag.identifier or "")
                    reaper.ImGui_Text(ctx, indicator_text)
                    reaper.ImGui_PopStyleColor(ctx)
                end
            end
        else
            -- No active fragments - show placeholder
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), 0x888888FF)
            reaper.ImGui_Text(ctx, "---")
            reaper.ImGui_PopStyleColor(ctx)
        end

        -- Progress bar + countdown to next VO (or end of current if last)
        local time_to_next, is_counting_to_end = get_time_to_next_vo(scenario_engine, vo_fragments)
        if time_to_next and time_to_next > 0 then
            -- Track max time for progress calculation
            if not progress_state.start_time or time_to_next > progress_state.start_time then
                progress_state.start_time = time_to_next
            end

            -- Reset if we passed a VO (time jumped up significantly)
            if time_to_next > progress_state.start_time + 1 then
                progress_state.start_time = time_to_next
            end

            -- Calculate progress (1.0 = full, 0.0 = empty)
            local progress = time_to_next / math.max(progress_state.start_time, 0.1)
            progress = math.max(0, math.min(1, progress))

            -- Draw progress bar at bottom
            local win_w, win_h = reaper.ImGui_GetWindowSize(ctx)
            local bar_height = 4
            local bar_y = win_h - bar_height - 2
            local bar_width = win_w * progress

            local draw_list = reaper.ImGui_GetWindowDrawList(ctx)
            local win_x, win_y = reaper.ImGui_GetWindowPos(ctx)

            -- Bar color: orange for next, green for end of current (last)
            local bar_color = is_counting_to_end and 0x44CC66FF or 0xFFAA44FF

            reaper.ImGui_DrawList_AddRectFilled(
                draw_list,
                win_x + 2, win_y + bar_y,
                win_x + bar_width - 2, win_y + bar_y + bar_height,
                bar_color
            )
        else
            -- No next VO - reset progress state
            progress_state.start_time = nil
        end

        reaper.ImGui_End(ctx)
    end

    reaper.ImGui_PopStyleVar(ctx)     -- WindowBorderSize
    reaper.ImGui_PopStyleColor(ctx, 2)  -- WindowBg, Border

    -- Handle window close
    if not open then
        Teleprompter.enabled = false
    end

    -- Save position if changed (debounced - only when toggled off or periodically)
    if position_dirty then
        Teleprompter.save_config()
        position_dirty = false
    end
end

--- Get current settings for display in settings panel
function Teleprompter.get_settings()
    return {
        font_size = font_size,
        opacity = bg_opacity,
    }
end

--- Set font size
function Teleprompter.set_font_size(new_size)
    font_size = math.max(12, math.min(72, new_size))
    position_dirty = true
end

--- Set background opacity
function Teleprompter.set_opacity(new_opacity)
    bg_opacity = math.max(0.1, math.min(1.0, new_opacity))
    position_dirty = true
end

-- ═══════════════════════════════════════════════════════════════════════════
-- CHECKPOINT: teleprompter.lua COMPLETE
-- ═══════════════════════════════════════════════════════════════════════════
-- Exported:
--   Teleprompter.init(ctx, fonts)
--   Teleprompter.toggle() -> bool
--   Teleprompter.is_enabled() -> bool
--   Teleprompter.render(ctx, fragments, markdown_lines, scenario_engine)
--   Teleprompter.get_settings() -> {font_size, opacity}
--   Teleprompter.set_font_size(size)
--   Teleprompter.set_opacity(opacity)
--   Teleprompter.load_config()
--   Teleprompter.save_config()
-- ═══════════════════════════════════════════════════════════════════════════

return Teleprompter
