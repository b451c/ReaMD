-- utils.lua
-- Zero-dependency utility module for ReaMD
-- Cross-platform path, file, string, and error handling utilities

local Utils = {}

-- ═══════════════════════════════════════════════════════════════════════════
-- PATH UTILITIES
-- ═══════════════════════════════════════════════════════════════════════════

-- Path separator for current OS (extracted from package.config)
-- package.config format: "sep\n...\n" where sep is the directory separator
Utils.SEP = package.config:sub(1, 1)

--- Normalize path separators for current OS
-- Converts forward/back slashes to the OS-appropriate separator
-- @param path string: Path to normalize
-- @return string: Normalized path
function Utils.normalize_path(path)
    if not path then return nil end

    -- Replace both types of slashes with the OS separator
    local normalized = path:gsub("[/\\]", Utils.SEP)

    -- Remove duplicate separators (but preserve UNC paths on Windows)
    if Utils.SEP == "\\" then
        -- Windows: preserve leading \\ for UNC paths
        local prefix = ""
        if normalized:sub(1, 2) == "\\\\" then
            prefix = "\\\\"
            normalized = normalized:sub(3)
        end
        normalized = prefix .. normalized:gsub("\\\\+", "\\")
    else
        -- Unix: simple duplicate removal
        normalized = normalized:gsub("//+", "/")
    end

    return normalized
end

--- Join path segments with OS-appropriate separator
-- @param ... string: Path segments to join
-- @return string: Joined and normalized path
function Utils.join_path(...)
    local segments = {...}
    local result = {}

    for i, segment in ipairs(segments) do
        if segment and segment ~= "" then
            -- Normalize this segment first
            local normalized = Utils.normalize_path(segment)

            -- Remove trailing separator from segment (unless it's the only char)
            if #normalized > 1 and normalized:sub(-1) == Utils.SEP then
                normalized = normalized:sub(1, -2)
            end

            -- Remove leading separator from non-first segments
            if #result > 0 and normalized:sub(1, 1) == Utils.SEP then
                normalized = normalized:sub(2)
            end

            if normalized ~= "" then
                table.insert(result, normalized)
            end
        end
    end

    return table.concat(result, Utils.SEP)
end

--- Extract directory from path
-- @param path string: Full path
-- @return string: Directory portion, or "." if no directory
function Utils.get_directory(path)
    if not path then return nil end

    local normalized = Utils.normalize_path(path)

    -- Find last separator
    local last_sep = nil
    for i = #normalized, 1, -1 do
        if normalized:sub(i, i) == Utils.SEP then
            last_sep = i
            break
        end
    end

    if not last_sep then
        return "."
    elseif last_sep == 1 then
        return Utils.SEP
    else
        return normalized:sub(1, last_sep - 1)
    end
end

--- Extract filename from path
-- @param path string: Full path
-- @return string: Filename portion
function Utils.get_filename(path)
    if not path then return nil end

    local normalized = Utils.normalize_path(path)

    -- Find last separator
    for i = #normalized, 1, -1 do
        if normalized:sub(i, i) == Utils.SEP then
            return normalized:sub(i + 1)
        end
    end

    -- No separator found, entire path is filename
    return normalized
end

-- ═══════════════════════════════════════════════════════════════════════════
-- FILE UTILITIES
-- ═══════════════════════════════════════════════════════════════════════════

--- Check if file exists
-- @param path string: Path to check
-- @return boolean: True if file exists and is readable
function Utils.file_exists(path)
    if not path then return false end

    local file = io.open(path, "r")
    if file then
        file:close()
        return true
    end
    return false
end

--- Read entire file contents
-- @param path string: Path to file
-- @return string|nil: File contents, or nil on error
-- @return string|nil: Error message on failure
function Utils.read_file(path)
    if not path then
        return nil, "No path provided"
    end

    local file, err = io.open(path, "r")
    if not file then
        return nil, "Cannot open file: " .. (err or "unknown error")
    end

    local content, read_err = file:read("*a")
    file:close()

    if not content then
        return nil, "Cannot read file: " .. (read_err or "unknown error")
    end

    return content
end

--- Write content to file
-- @param path string: Path to file
-- @param content string: Content to write
-- @return boolean: True on success
-- @return string|nil: Error message on failure
function Utils.write_file(path, content)
    if not path then
        return false, "No path provided"
    end

    if content == nil then
        return false, "No content provided"
    end

    local file, err = io.open(path, "w")
    if not file then
        return false, "Cannot open file for writing: " .. (err or "unknown error")
    end

    local success, write_err = file:write(content)
    file:close()

    if not success then
        return false, "Cannot write to file: " .. (write_err or "unknown error")
    end

    return true
end

-- ═══════════════════════════════════════════════════════════════════════════
-- STRING UTILITIES
-- ═══════════════════════════════════════════════════════════════════════════

--- Trim whitespace from both ends of string
-- @param str string: String to trim
-- @return string: Trimmed string
function Utils.trim(str)
    if not str then return nil end

    -- Match non-whitespace content, or return empty string
    return str:match("^%s*(.-)%s*$") or ""
end

--- Split string by separator
-- @param str string: String to split
-- @param sep string: Separator (default: ",")
-- @return table: Array of substrings
function Utils.split(str, sep)
    if not str then return {} end

    sep = sep or ","
    local result = {}

    -- Handle empty separator - split into characters
    if sep == "" then
        for i = 1, #str do
            table.insert(result, str:sub(i, i))
        end
        return result
    end

    -- Pattern-escape the separator for use in gsub/match
    local pattern = "([^" .. sep:gsub("([^%w])", "%%%1") .. "]*)"

    -- Simple split using gmatch
    local pos = 1
    while pos <= #str + 1 do
        local start_pos, end_pos = str:find(sep, pos, true)
        if start_pos then
            table.insert(result, str:sub(pos, start_pos - 1))
            pos = end_pos + 1
        else
            table.insert(result, str:sub(pos))
            break
        end
    end

    return result
end

-- ═══════════════════════════════════════════════════════════════════════════
-- ERROR HANDLING
-- ═══════════════════════════════════════════════════════════════════════════

--- Safe function call wrapper (pcall with cleaner return values)
-- @param fn function: Function to call
-- @param ... any: Arguments to pass to function
-- @return any|nil: Result of function, or nil on error
-- @return string|nil: Error message on failure
function Utils.safe_call(fn, ...)
    if type(fn) ~= "function" then
        return nil, "Not a function"
    end

    local success, result = pcall(fn, ...)

    if success then
        return result
    else
        return nil, tostring(result)
    end
end

-- ═══════════════════════════════════════════════════════════════════════════
-- CHECKPOINT: utils.lua COMPLETE
-- Exported: Utils.SEP, normalize_path, join_path, get_directory, get_filename
--           file_exists, read_file, write_file, trim, split, safe_call
-- ═══════════════════════════════════════════════════════════════════════════

return Utils
