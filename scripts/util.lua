-- Utility functions for agricultural-roboport mod

local util = {}

-- Logging utility
function util.write_file_log(...)
    local ok = false
    if settings and settings.global and settings.global["agricultural-roboport-debug"] then
        ok = settings.global["agricultural-roboport-debug"].value
    end
    if not ok then return end
    if not (helpers and helpers.write_file) then return end
    local parts = {}
    local n = select('#', ...)
    for i = 1, n do
        local v = select(i, ...)
        if type(v) == "string" then
            parts[#parts+1] = v
        else
            if serpent and serpent.block then
                parts[#parts+1] = serpent.block(v)
            else
                parts[#parts+1] = tostring(v)
            end
        end
    end
    helpers.write_file("agricultural-roboport.log", table.concat(parts, " ") .. "\n", true)
end

-- Helper to count table entries
function util.table_size(t)
    local count = 0
    for _ in pairs(t) do count = count + 1
    end
    return count
end

-- Helper to clamp values
function util.clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

return util
