-- cue_list.lua
-- Floating panel listing all linked fragments sorted by earliest item time.
-- Click a row -> jump to item on timeline + scroll the markdown viewer to that line.

local CueList = {}

-- ─────────────────────────────────────────────────────────────────────────────
-- STATE
-- ─────────────────────────────────────────────────────────────────────────────

CueList.visible = false
CueList.filter = ""   -- text filter (search inside cue list)

-- ─────────────────────────────────────────────────────────────────────────────
-- PUBLIC API
-- ─────────────────────────────────────────────────────────────────────────────

function CueList.is_visible()
    return CueList.visible
end

function CueList.show()
    CueList.visible = true
end

function CueList.hide()
    CueList.visible = false
end

function CueList.toggle()
    CueList.visible = not CueList.visible
    return CueList.visible
end

--- Build the sorted row list from the scenario engine's fragment map.
-- @param scenario_engine table: ScenarioEngine module
-- @return table: list of { pos, end_pos, frag, items_count }, sorted by pos ascending
local function build_rows(scenario_engine)
    local rows = {}
    local fragments = scenario_engine.fragment_map
        and scenario_engine.fragment_map.fragments or {}

    for _, frag in ipairs(fragments) do
        local guids = frag.item_guids
        if not guids and frag.item_guid then guids = {frag.item_guid} end

        local start_pos, end_pos
        local count = 0
        if guids then
            for _, guid in ipairs(guids) do
                local s, e = scenario_engine.get_item_bounds(guid)
                if s then
                    if not start_pos or s < start_pos then start_pos = s end
                    if not end_pos or e > end_pos then end_pos = e end
                    count = count + 1
                end
            end
        end

        if start_pos then
            table.insert(rows, {
                pos = start_pos,
                end_pos = end_pos or start_pos,
                frag = frag,
                items_count = count,
            })
        elseif frag.region_id then
            -- Legacy region-based fragment
            for _, r in ipairs(scenario_engine.regions or {}) do
                if r.id == frag.region_id then
                    table.insert(rows, {
                        pos = r.pos, end_pos = r.rgnend,
                        frag = frag, items_count = 0,
                    })
                    break
                end
            end
        end
    end

    table.sort(rows, function(a, b) return a.pos < b.pos end)
    return rows
end

local function format_time(seconds)
    if not seconds or seconds < 0 then return "—" end
    local total = math.floor(seconds + 0.5)
    local h = math.floor(total / 3600)
    local m = math.floor((total % 3600) / 60)
    local s = total % 60
    if h > 0 then
        return string.format("%d:%02d:%02d", h, m, s)
    end
    return string.format("%d:%02d", m, s)
end

local function format_duration(start_pos, end_pos)
    if not start_pos or not end_pos or end_pos <= start_pos then return "" end
    return format_time(end_pos - start_pos)
end

--- Render the Cue List window
-- @param ctx ReaImGui context
-- @param scenario_engine table: ScenarioEngine module
-- @param on_jump function(frag): callback when user clicks a cue (e.g. scroll to line)
function CueList.render(ctx, scenario_engine, on_jump)
    if not CueList.visible then return end

    reaper.ImGui_SetNextWindowSize(ctx, 480, 360, reaper.ImGui_Cond_FirstUseEver())
    local window_flags = reaper.ImGui_WindowFlags_NoCollapse()
    local visible, open = reaper.ImGui_Begin(ctx, "ReaMD - Cue List", true, window_flags)

    if visible then
        -- Filter input
        reaper.ImGui_SetNextItemWidth(ctx, -1)
        local changed, new_filter = reaper.ImGui_InputTextWithHint(
            ctx, "##cue_filter", "Filter cues...", CueList.filter or "")
        if changed then CueList.filter = new_filter end

        reaper.ImGui_Spacing(ctx)

        -- Build sorted rows
        local rows = build_rows(scenario_engine)
        local filter_lc = (CueList.filter or ""):lower()

        -- Stats line
        reaper.ImGui_TextDisabled(ctx,
            string.format("%d cue(s) total", #rows))
        reaper.ImGui_Separator(ctx)

        -- Table
        local table_flags = reaper.ImGui_TableFlags_Borders()
                         + reaper.ImGui_TableFlags_RowBg()
                         + reaper.ImGui_TableFlags_ScrollY()
                         + reaper.ImGui_TableFlags_Resizable()

        if reaper.ImGui_BeginTable(ctx, "cue_table", 5, table_flags) then
            reaper.ImGui_TableSetupColumn(ctx, "Time",
                reaper.ImGui_TableColumnFlags_WidthFixed(), 60)
            reaper.ImGui_TableSetupColumn(ctx, "Dur",
                reaper.ImGui_TableColumnFlags_WidthFixed(), 50)
            reaper.ImGui_TableSetupColumn(ctx, "Cat",
                reaper.ImGui_TableColumnFlags_WidthFixed(), 30)
            reaper.ImGui_TableSetupColumn(ctx, "Identifier",
                reaper.ImGui_TableColumnFlags_WidthStretch())
            reaper.ImGui_TableSetupColumn(ctx, "#",
                reaper.ImGui_TableColumnFlags_WidthFixed(), 30)
            reaper.ImGui_TableHeadersRow(ctx)

            for _, row in ipairs(rows) do
                local frag = row.frag
                local id = (frag.identifier or frag.heading or ""):lower()

                if filter_lc == "" or id:find(filter_lc, 1, true) then
                    reaper.ImGui_TableNextRow(ctx)

                    -- Time column (clickable selectable spanning all columns)
                    reaper.ImGui_TableSetColumnIndex(ctx, 0)
                    local time_label = format_time(row.pos) .. "##cue_" .. tostring(frag.line_start)
                    local clicked = reaper.ImGui_Selectable(ctx, time_label, false,
                        reaper.ImGui_SelectableFlags_SpanAllColumns())
                    if clicked then
                        -- Jump to first item & notify caller to scroll markdown
                        local guids = frag.item_guids or (frag.item_guid and {frag.item_guid}) or {}
                        if guids[1] then
                            scenario_engine.jump_to_item(guids[1])
                        end
                        if on_jump then on_jump(frag) end
                    end

                    -- Duration
                    reaper.ImGui_TableSetColumnIndex(ctx, 1)
                    reaper.ImGui_Text(ctx, format_duration(row.pos, row.end_pos))

                    -- Category badge
                    reaper.ImGui_TableSetColumnIndex(ctx, 2)
                    local cat = scenario_engine.get_color_category_info(frag.color_category)
                    if cat then
                        reaper.ImGui_TextColored(ctx, cat.button_color, cat.label or "?")
                    end

                    -- Identifier
                    reaper.ImGui_TableSetColumnIndex(ctx, 3)
                    reaper.ImGui_Text(ctx, frag.identifier or frag.heading or "")

                    -- Item count
                    reaper.ImGui_TableSetColumnIndex(ctx, 4)
                    reaper.ImGui_Text(ctx, tostring(row.items_count))
                end
            end

            reaper.ImGui_EndTable(ctx)
        end

        reaper.ImGui_End(ctx)
    end

    if not open then
        CueList.visible = false
    end
end

return CueList
