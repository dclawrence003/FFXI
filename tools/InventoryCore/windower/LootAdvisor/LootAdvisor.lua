_addon.name = 'LootAdvisor'
_addon.author = 'Dolomedes + Codex'
_addon.version = '0.1.0'
_addon.commands = {'la', 'lootadvisor'}

require('tables')
local res = require('resources')
local http = require('socket.http')
local json = require('json')
local cache = {items = {}, generated_at = 'not loaded'}
local seen = {}
local last_scan = 0
http.TIMEOUT = 2

local colors = {KEEP=158, UPGRADE=159, AH=205, HOLD=200, REVIEW=207, VENDOR=057, DROP=167}

local function load_cache()
    local ok, data = pcall(dofile, windower.addon_path .. 'data/recommendations.lua')
    if ok and type(data) == 'table' then
        cache = data
        windower.add_to_chat(158, ('LootAdvisor: cache loaded (%s).'):format(cache.generated_at or 'unknown'))
    else
        windower.add_to_chat(167, 'LootAdvisor: recommendation cache is missing. Run InventoryCore refresh.')
    end
end

local function live_recommendation(item_id)
    local ok, body, code = pcall(
        http.request,
        ('http://127.0.0.1:8787/api/loot?id=%d'):format(item_id))
    if not ok or tonumber(code) ~= 200 or not body then
        return nil
    end

    local parsed_ok, row = pcall(json.parse, body)
    if not parsed_ok or type(row) ~= 'table' or not row.action then
        return nil
    end
    return row
end

local function recommendation(item_id)
    local row = cache.items and cache.items[item_id]
    if row then return row end

    row = live_recommendation(item_id)
    if row then
        if not row.market_pending then
            cache.items[item_id] = row
        end
        return row
    end

    local item = res.items[item_id]
    return nil, item and item.en or ('Item ' .. tostring(item_id))
end

local function show(item_id, show_unindexed)
    local row, unindexed_name = recommendation(item_id)
    if not row then
        windower.add_to_chat(167, ('[LA] LOOKUP FAILED %s'):format(unindexed_name))
        if show_unindexed then
            windower.add_to_chat(
                167,
                '[LA]   InventoryCore is unavailable at http://127.0.0.1:8787.')
        end
        return false
    end

    local owner = row.owners ~= '' and (' | Own: ' .. row.owners) or ''
    windower.add_to_chat(colors[row.action] or 207,
        ('[LA] %s [%s] %s'):format(
            row.action, (row.confidence or 'unknown'):upper(), row.name))
    windower.add_to_chat(colors[row.action] or 207,
        ('[LA]   %s%s'):format(row.reason, owner))
    return true
end

local function scan_pool(force)
    local treasure = windower.ffxi.get_items('treasure') or {}
    local present = {}
    for index = 0, 9 do
        local slot = treasure[index]
        if slot and slot.item_id and slot.item_id > 0 then
            present[index] = slot.item_id
            local signature = tostring(index) .. ':' .. tostring(slot.item_id)
            if force or not seen[signature] then
                show(slot.item_id, false)
                seen[signature] = true
            end
        end
    end
    for signature in pairs(seen) do
        local index, item_id = signature:match('^(%d+):(%d+)$')
        if not present[tonumber(index)] or present[tonumber(index)] ~= tonumber(item_id) then
            seen[signature] = nil
        end
    end
end

windower.register_event('load', load_cache)
windower.register_event('prerender', function()
    local now = os.clock()
    if now - last_scan >= 1 then
        last_scan = now
        scan_pool(false)
    end
end)

windower.register_event('addon command', function(command, ...)
    command = command and command:lower() or 'help'
    if command == 'pool' then
        scan_pool(true)
    elseif command == 'reload' or command == 'refresh' then
        load_cache()
    elseif command == 'item' then
        local query = table.concat({...}, ' '):lower()
        for id, item in pairs(res.items) do
            if item.en and item.en:lower() == query then show(id, true) return end
        end
        windower.add_to_chat(167, 'LootAdvisor: item not found: ' .. query)
    else
        windower.add_to_chat(207, 'LootAdvisor commands: //la pool | //la item <name> | //la reload')
    end
end)
