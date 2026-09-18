local M = {}

local function filename_id(entry)
    if type(entry) ~= 'string' then return nil end
    entry = entry:gsub('[\\/]+$', ''):match('([^\\/]+)$') or entry
    return entry:match('^([a-z0-9][a-z0-9_-]*)%.lua$')
end

function M.discover(util, root, get_dir, file_exists, load_file, source_digest)
    local adapters, errors, entries = {}, {}, {}
    for _, entry in pairs(get_dir(root) or {}) do entries[#entries + 1] = entry end
    table.sort(entries, function(left, right)
        return tostring(left):lower() < tostring(right):lower()
    end)
    for _, entry in ipairs(entries) do
        local id = filename_id(entry)
        local path = id and root..id..'.lua' or nil
        if id and util.valid_id(id, 32) and file_exists(path) then
            local loader, load_error = load_file(path)
            if not loader then
                errors[#errors + 1] = id..': '..tostring(load_error)
            else
                local ok, adapter = pcall(loader)
                if not ok or type(adapter) ~= 'table'
                    or adapter.id ~= id or type(adapter.execute) ~= 'function'
                then
                    errors[#errors + 1] = id..': invalid adapter'
                elseif adapters[id] then
                    errors[#errors + 1] = id..': duplicate adapter'
                else
                    adapter.__source_digest = source_digest
                        and source_digest(path) or 'unavailable'
                    adapters[id] = adapter
                end
            end
        end
    end
    return adapters, errors
end

return M
