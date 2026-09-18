local M = {}

local function copy_array(values)
    local result = {}
    for _, value in ipairs(values or {}) do result[#result + 1] = value end
    return result
end

local function filename_id(entry)
    if type(entry) ~= 'string' then return nil end
    entry = entry:gsub('[\\/]+$', ''):match('([^\\/]+)$') or entry
    return entry:match('^([a-z0-9][a-z0-9%-]*)%.lua$')
end

local function valid_identity(util, identity, filename)
    if type(identity) ~= 'table'
        or not util.valid_id(identity.id, 64)
        or identity.id ~= filename
        or type(identity.ordinal) ~= 'number'
        or identity.ordinal < 1 or identity.ordinal % 1 ~= 0
        or not util.valid_id(identity.policy_id, 64)
        or type(identity.aliases) ~= 'table'
    then return false end
    local seen = {[identity.id]=true}
    for _, alias in ipairs(identity.aliases) do
        if not util.valid_id(alias, 64) or seen[alias] then return false end
        seen[alias] = true
    end
    return true
end

-- The base registry is frozen. Each future profile contributes one new file,
-- so a malformed addition is quarantined without making the established
-- registry chunk unloadable. Only the next ordinal is accepted; gaps and
-- duplicates cannot reorder prior ownership.
function M.extend(util, base, root, get_dir, file_exists, load_file)
    local result = {
        schema=base and base.schema,
        reserved_commands=copy_array(base and base.reserved_commands),
        identities=copy_array(base and base.identities),
    }
    local errors, candidates = {}, {}
    local entries = {}
    for _, entry in pairs(get_dir(root) or {}) do entries[#entries + 1] = entry end
    table.sort(entries, function(left, right)
        return tostring(left):lower() < tostring(right):lower()
    end)
    for _, entry in ipairs(entries) do
        local id = filename_id(entry)
        local path = id and root..id..'.lua' or nil
        if id and file_exists(path) then
            local loader, load_error = load_file(path)
            if not loader then
                errors[#errors + 1] = id..': '..tostring(load_error)
            else
                local ok, identity = pcall(loader)
                if not ok or not valid_identity(util, identity, id) then
                    errors[#errors + 1] = id
                        ..': invalid isolated profile identity.'
                else
                    candidates[#candidates + 1] = identity
                end
            end
        end
    end
    table.sort(candidates, function(left, right)
        if left.ordinal ~= right.ordinal then
            return left.ordinal < right.ordinal
        end
        return left.id < right.id
    end)
    local next_ordinal = #result.identities + 1
    for _, identity in ipairs(candidates) do
        if identity.ordinal ~= next_ordinal then
            errors[#errors + 1] = identity.id..': identity ordinal '
                ..tostring(identity.ordinal)..' is not the next append-only '
                ..'ordinal '..tostring(next_ordinal)..'.'
        else
            result.identities[#result.identities + 1] = identity
            next_ordinal = next_ordinal + 1
        end
    end
    return result, errors
end

return M
