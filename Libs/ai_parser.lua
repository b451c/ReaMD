-- ai_parser.lua
-- AI-powered text formatting module for ReaMD
-- Uses Claude API via async curl calls

local AIParser = {}

-- ═══════════════════════════════════════════════════════════════════════════
-- DEPENDENCIES
-- ═══════════════════════════════════════════════════════════════════════════

-- These will be set by init()
local Utils = nil
local Config = nil
local json = nil

-- ═══════════════════════════════════════════════════════════════════════════
-- STATE
-- ═══════════════════════════════════════════════════════════════════════════

AIParser.state = {
    -- Window state
    show_window = false,
    input_text = "",

    -- Async operation state
    is_loading = false,
    temp_file = nil,           -- Path to response temp file
    start_time = nil,          -- For timeout tracking

    -- Result state
    result_markdown = nil,
    error_message = nil,
}

-- Timeout in seconds
local API_TIMEOUT = 120

-- Project directory (set by init)
local project_dir = nil

-- ═══════════════════════════════════════════════════════════════════════════
-- INITIALIZATION
-- ═══════════════════════════════════════════════════════════════════════════

--- Initialize the AI Parser module
-- @param utils_module table: Utils module
-- @param config_module table: Config module
-- @param json_module table: JSON module
-- @param proj_dir string: Project directory path
function AIParser.init(utils_module, config_module, json_module, proj_dir)
    Utils = utils_module
    Config = config_module
    json = json_module
    project_dir = proj_dir
end

-- ═══════════════════════════════════════════════════════════════════════════
-- PROMPT MANAGEMENT
-- ═══════════════════════════════════════════════════════════════════════════

--- Get default prompt file path
-- @return string: Path to default prompt file
function AIParser.get_default_prompt_path()
    if not project_dir then
        return nil
    end
    return Utils.join_path(project_dir, "prompts", "ai_format_prompt.txt")
end

--- Get current prompt text
-- @return string: Prompt text to use for API call
function AIParser.get_prompt()
    local prompt_path = AIParser.get_default_prompt_path()

    if prompt_path then
        local content, err = Utils.read_file(prompt_path)
        if content then
            return content
        end
    end

    -- Fallback prompt if file doesn't exist
    return [[You are a markdown formatting assistant.

Convert the following unformatted text into clean, well-structured markdown.

Guidelines:
- Use heading levels appropriately (# for main sections, ## for subsections)
- Use bullet lists for items, numbered lists for sequences
- Use **bold** for emphasis on key terms
- Preserve all original content - do not add or remove information

Output ONLY the formatted markdown. Do not include any explanations.]]
end

--- Open prompt file in system editor
function AIParser.open_prompt_editor()
    local prompt_path = AIParser.get_default_prompt_path()

    if not prompt_path then
        reaper.MB("Cannot determine prompt file path", "ReaMD Error", 0)
        return
    end

    -- Ensure prompt file exists
    if not Utils.file_exists(prompt_path) then
        -- Create default prompt file
        local default_prompt = AIParser.get_prompt()

        -- Create prompts directory if needed
        local prompts_dir = Utils.get_directory(prompt_path)
        local sep = Utils.SEP
        local mkdir_cmd = sep == "\\"
            and ('mkdir "' .. prompts_dir .. '" 2>nul')
            or ('mkdir -p "' .. prompts_dir .. '"')
        os.execute(mkdir_cmd)

        Utils.write_file(prompt_path, default_prompt)
    end

    -- Try to open in system editor
    if reaper.CF_ShellExecute then
        -- SWS extension available
        reaper.CF_ShellExecute(prompt_path)
    else
        -- Fallback: show path in message box
        reaper.MB(
            "SWS extension not installed.\n\nManually edit the prompt file at:\n\n" .. prompt_path,
            "Edit Prompt",
            0
        )
    end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- ASYNC API CALL
-- ═══════════════════════════════════════════════════════════════════════════

-- Default model if user hasn't picked one
local DEFAULT_MODEL = "claude-haiku-4-5-20251001"

--- Detect Windows platform.
-- @return boolean
local function is_windows()
    local ok, os_name = pcall(reaper.GetOS)
    if ok and os_name and os_name:match("Win") then
        return true
    end
    -- Fallback to path separator
    return Utils.SEP == "\\"
end

--- Generate temporary file path
-- @return string: Path for temp file
local function get_temp_file()
    local temp_dir
    if is_windows() then
        temp_dir = os.getenv("TEMP") or os.getenv("TMP") or "C:\\Windows\\Temp"
    else
        temp_dir = os.getenv("TMPDIR") or "/tmp"
    end
    -- Use os.time + a random suffix to avoid collisions when user fires multiple parses quickly
    local suffix = tostring(os.time()) .. "_" .. tostring(math.random(1000, 9999))
    return Utils.join_path(temp_dir, "reamd_ai_response_" .. suffix .. ".json")
end

--- Validate that the API key looks plausible
-- @param key string
-- @return boolean, string|nil: ok, error message
local function validate_api_key(key)
    if not key or key == "" then
        return false, "No API key configured. Set it in Settings."
    end
    if not key:match("^sk%-ant%-") then
        return false, "API key looks invalid (expected 'sk-ant-...' format)."
    end
    return true
end

--- Build the request body JSON for the Anthropic Messages API
local function build_request_body(prompt, input_text)
    local model = (Config and Config.get and Config.get("ai_model")) or DEFAULT_MODEL
    if not model or model == "" then model = DEFAULT_MODEL end
    return json.encode({
        model = model,
        max_tokens = 8192,
        messages = {
            {
                role = "user",
                content = prompt .. "\n\n---\n\nText to format:\n\n" .. input_text
            }
        }
    })
end

--- Spawn the curl process in the background, OS-aware.
-- Returns true on apparent successful spawn (we can't truly know without polling).
local function spawn_curl(temp_file, request_file, api_key)
    local script_path, launch_cmd

    if is_windows() then
        script_path = temp_file .. ".bat"
        -- Windows batch: caret (^) line continuation, double quotes around paths.
        local script_content = string.format(
            '@echo off\r\n' ..
            'curl -s -o "%s" -X POST "https://api.anthropic.com/v1/messages" ^\r\n' ..
            '  -H "Content-Type: application/json" ^\r\n' ..
            '  -H "x-api-key: %s" ^\r\n' ..
            '  -H "anthropic-version: 2023-06-01" ^\r\n' ..
            '  -d @"%s"\r\n',
            temp_file, api_key, request_file
        )
        local ok = Utils.write_file(script_path, script_content)
        if not ok then return false, "Failed to create launcher script (.bat)" end
        -- Run detached so REAPER doesn't block. start "" /B suppresses a new window.
        launch_cmd = 'start "" /B "' .. script_path .. '"'
    else
        script_path = temp_file .. ".sh"
        local script_content = string.format(
            "#!/bin/sh\n" ..
            'curl -s -o "%s" -X POST "https://api.anthropic.com/v1/messages" \\\n' ..
            '  -H "Content-Type: application/json" \\\n' ..
            '  -H "x-api-key: %s" \\\n' ..
            '  -H "anthropic-version: 2023-06-01" \\\n' ..
            '  -d @"%s"\n',
            temp_file, api_key, request_file
        )
        local ok = Utils.write_file(script_path, script_content)
        if not ok then return false, "Failed to create launcher script (.sh)" end
        os.execute('chmod +x "' .. script_path .. '"')
        launch_cmd = '"' .. script_path .. '" &'
    end

    os.execute(launch_cmd)
    return true
end

--- Start async API call
-- @param input_text string: Text to format
-- @return boolean: True if call started successfully
function AIParser.start_api_call(input_text)
    if not json then
        AIParser.state.error_message = "JSON module not initialized"
        return false
    end

    local api_key = Config.get("ai_api_key")
    local key_ok, key_err = validate_api_key(api_key)
    if not key_ok then
        AIParser.state.error_message = key_err
        return false
    end

    local prompt = AIParser.get_prompt()
    local request_body = build_request_body(prompt, input_text)

    -- Generate temp file for response
    local temp_file = get_temp_file()
    AIParser.state.temp_file = temp_file

    -- Write request body to temp file (avoids shell escaping issues for the JSON payload)
    local request_file = temp_file .. ".request"
    local ok, err = Utils.write_file(request_file, request_body)
    if not ok then
        AIParser.state.error_message = "Failed to write request: " .. (err or "")
        return false
    end

    -- Spawn the platform-appropriate launcher
    local spawned, spawn_err = spawn_curl(temp_file, request_file, api_key)
    if not spawned then
        AIParser.state.error_message = spawn_err or "Failed to launch curl"
        os.remove(request_file)
        return false
    end

    AIParser.state.is_loading = true
    AIParser.state.start_time = reaper.time_precise()
    AIParser.state.error_message = nil
    AIParser.state.result_markdown = nil
    return true
end

--- Poll for API response (call in defer loop)
-- @return boolean: True if still loading, false if complete or error
function AIParser.poll_response()
    if not AIParser.state.is_loading then
        return false
    end

    -- Check timeout
    local elapsed = reaper.time_precise() - AIParser.state.start_time
    if elapsed > API_TIMEOUT then
        AIParser.state.is_loading = false
        AIParser.state.error_message = "API request timed out after " .. API_TIMEOUT .. "s"
        AIParser.cleanup_temp_files()
        return false
    end

    -- Check if response file exists and has content
    local temp_file = AIParser.state.temp_file
    if not temp_file then
        return true
    end

    if not Utils.file_exists(temp_file) then
        -- Still waiting
        return true
    end

    local content = Utils.read_file(temp_file)
    if not content or content == "" then
        -- File exists but empty - still writing
        return true
    end

    -- Response received - parse it
    AIParser.state.is_loading = false

    local success, response = pcall(json.decode, content)
    if not success then
        -- Show a snippet of the bad content (helps diagnose curl / network issues)
        local snippet = content:sub(1, 200)
        AIParser.state.error_message =
            "Failed to parse API response.\nFirst bytes: " .. snippet
        AIParser.cleanup_temp_files()
        return false
    end

    -- Check for API error (Anthropic returns { type:"error", error:{type,message} })
    if response.error then
        local et = response.error.type or "error"
        local em = response.error.message or "(no message)"
        AIParser.state.error_message = "API " .. et .. ": " .. em
        AIParser.cleanup_temp_files()
        return false
    end

    -- Extract markdown from response
    if response.content and response.content[1] and response.content[1].text then
        AIParser.state.result_markdown = response.content[1].text
        -- Keep usage info for potential display (cost estimate, etc.)
        AIParser.state.last_usage = response.usage
        AIParser.state.last_model = response.model
    else
        AIParser.state.error_message =
            "Unexpected API response format (no content[].text)"
        AIParser.cleanup_temp_files()
        return false
    end

    -- Clean up temp files
    AIParser.cleanup_temp_files()

    return false
end

--- Clean up temporary files (both .sh and .bat suffix variants)
function AIParser.cleanup_temp_files()
    if AIParser.state.temp_file then
        os.remove(AIParser.state.temp_file)
        os.remove(AIParser.state.temp_file .. ".request")
        os.remove(AIParser.state.temp_file .. ".sh")
        os.remove(AIParser.state.temp_file .. ".bat")
        AIParser.state.temp_file = nil
    end
end

--- Cancel ongoing request
function AIParser.cancel()
    AIParser.state.is_loading = false
    AIParser.cleanup_temp_files()
end

--- Reset state for new operation
function AIParser.reset()
    AIParser.state.input_text = ""
    AIParser.state.result_markdown = nil
    AIParser.state.error_message = nil
    AIParser.state.is_loading = false
end

-- ═══════════════════════════════════════════════════════════════════════════
-- WINDOW CONTROL
-- ═══════════════════════════════════════════════════════════════════════════

function AIParser.show()
    AIParser.reset()
    AIParser.state.show_window = true
end

function AIParser.hide()
    AIParser.cancel()
    AIParser.state.show_window = false
end

function AIParser.is_visible()
    return AIParser.state.show_window
end

-- ═══════════════════════════════════════════════════════════════════════════
-- CHECKPOINT: ai_parser.lua COMPLETE
-- ═══════════════════════════════════════════════════════════════════════════
-- Exported:
--   AIParser.init(utils, config, json, project_dir)
--   AIParser.get_default_prompt_path() -> string
--   AIParser.get_prompt() -> string
--   AIParser.open_prompt_editor()
--   AIParser.start_api_call(input_text) -> bool
--   AIParser.poll_response() -> bool (true = still loading)
--   AIParser.cancel()
--   AIParser.reset()
--   AIParser.show()
--   AIParser.hide()
--   AIParser.is_visible() -> bool
--   AIParser.state (table with: show_window, input_text, is_loading,
--                   result_markdown, error_message)
-- ═══════════════════════════════════════════════════════════════════════════

return AIParser
