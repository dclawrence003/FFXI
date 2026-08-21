_addon.name = 'LootAdvisor'
_addon.author = 'Dolomedes + Codex'
_addon.version = '0.2.2'
_addon.commands = {'la', 'lootadvisor'}

require('tables')
local packets = require('packets')
local ltn12 = require('ltn12')
local res = require('resources')
local http = require('socket.http')
local json = require('json')
local cache = {items = {}, generated_at = 'not loaded'}
local seen = {}
local last_scan = 0
-- LuaSocket requests execute on Windower's game thread. InventoryCore is a
-- localhost service, so a healthy request should complete almost immediately;
-- never let a dead or wedged backend stall a client for multiple seconds.
http.TIMEOUT = 0.10
local api_root = 'http://127.0.0.1:8787'
local currencies = {}
local last_telemetry = 0
local last_currency_request = 0
local api_failure_count = 0
local api_retry_at = 0
local api_offline = false

local API_INITIAL_BACKOFF = 60
local API_MAX_BACKOFF = 300

local colors = {KEEP=158, UPGRADE=159, AH=205, HOLD=200, REVIEW=207, VENDOR=057, DROP=167}

local function owner_text(value)
    if type(value) == 'string' then
        return value
    end
    if type(value) ~= 'table' then
        return ''
    end

    local owners = {}
    for _, owner in ipairs(value) do
        if type(owner) == 'table' then
            local name = owner.character or owner.name
            if name then
                owners[#owners + 1] = tostring(name) .. ' x' .. tostring(owner.count or 1)
            end
        elseif owner ~= nil then
            owners[#owners + 1] = tostring(owner)
        end
    end
    return table.concat(owners, ', ')
end

local function normalize_row(row, item_id)
    if type(row) ~= 'table' then
        return nil
    end

    local item = res.items[item_id]
    return {
        action = type(row.action) == 'string' and row.action:upper() or 'REVIEW',
        confidence = type(row.confidence) == 'string' and row.confidence or 'unknown',
        name = type(row.name) == 'string'
            and row.name
            or (item and item.en or ('Item ' .. tostring(item_id))),
        reason = type(row.reason) == 'string'
            and row.reason
            or 'Recommendation details were unavailable.',
        owners = owner_text(row.owners),
        market_pending = row.market_pending == true,
    }
end

local function load_cache()
    local ok, data = pcall(dofile, windower.addon_path .. 'data/recommendations.lua')
    if ok and type(data) == 'table' then
        cache = data
        windower.add_to_chat(158, ('LootAdvisor: cache loaded (%s).'):format(cache.generated_at or 'unknown'))
    else
        windower.add_to_chat(167, 'LootAdvisor: recommendation cache is missing. Run InventoryCore refresh.')
    end
end

local function api_can_attempt(force)
    if force then
        api_retry_at = 0
        return true
    end
    return os.time() >= api_retry_at
end

local function api_mark_failure()
    api_failure_count = api_failure_count + 1
    local backoff = math.min(
        API_MAX_BACKOFF,
        API_INITIAL_BACKOFF * (2 ^ math.min(api_failure_count - 1, 3)))
    api_retry_at = os.time() + backoff
    if not api_offline then
        api_offline = true
        windower.add_to_chat(123,
            ('[LA] InventoryCore is unavailable; localhost requests paused '
                ..'for %d seconds. Cached loot advice remains active.')
                :format(backoff))
    end
end

local function api_mark_success()
    if api_offline then
        windower.add_to_chat(158, '[LA] InventoryCore connection restored.')
    end
    api_offline = false
    api_failure_count = 0
    api_retry_at = 0
end

local function live_recommendation(item_id)
    if not api_can_attempt(false) then return nil end
    local ok, body, code = pcall(
        http.request,
        ('http://127.0.0.1:8787/api/loot?id=%d'):format(item_id))
    if not ok or not body or not tonumber(code) then
        api_mark_failure()
        return nil
    end
    api_mark_success()
    if tonumber(code) ~= 200 then return nil end

    local parsed_ok, row = pcall(json.parse, body)
    if not parsed_ok or type(row) ~= 'table' or not row.action then
        return nil
    end
    return row
end

local function recommendation(item_id)
    local row = cache.items and cache.items[item_id]
    if row then return normalize_row(row, item_id) end

    row = live_recommendation(item_id)
    if row then
        row = normalize_row(row, item_id)
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

local function json_escape(value)
    return tostring(value):gsub('[%z\1-\31\\"]', function(character)
        local replacements = {['"'] = '\\"', ['\\'] = '\\\\', ['\b'] = '\\b',
            ['\f'] = '\\f', ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t'}
        return replacements[character] or ('\\u%04x'):format(character:byte())
    end)
end

local function json_encode(value)
    local kind = type(value)
    if kind == 'nil' then return 'null' end
    if kind == 'boolean' then return value and 'true' or 'false' end
    if kind == 'number' then return tostring(value) end
    if kind == 'string' then return '"' .. json_escape(value) .. '"' end
    if kind ~= 'table' then return 'null' end

    local is_array, maximum = true, 0
    for key in pairs(value) do
        if type(key) ~= 'number' or key < 1 or key % 1 ~= 0 then
            is_array = false
            break
        end
        maximum = math.max(maximum, key)
    end
    local output = {}
    if is_array then
        for index = 1, maximum do output[#output + 1] = json_encode(value[index]) end
        return '[' .. table.concat(output, ',') .. ']'
    end
    for key, item in pairs(value) do
        output[#output + 1] = '"' .. json_escape(key) .. '":' .. json_encode(item)
    end
    table.sort(output)
    return '{' .. table.concat(output, ',') .. '}'
end

local function post_json(path, payload, force)
    if not api_can_attempt(force) then return false end
    local body = json_encode(payload)
    local response = {}
    local ok, request_ok, code = pcall(http.request, {
        url = api_root .. path,
        method = 'POST',
        headers = {
            ['Content-Type'] = 'application/json',
            ['Content-Length'] = tostring(#body),
        },
        source = ltn12.source.string(body),
        sink = ltn12.sink.table(response),
    })
    if not ok or not request_ok or not tonumber(code) then
        api_mark_failure()
        return false
    end
    api_mark_success()
    return tonumber(code) == 200
end

local function player_name()
    local player = windower.ffxi.get_player()
    return player and player.name or nil
end

local function collect_key_items()
    local output, owned = {}, windower.ffxi.get_key_items() or {}
    local seen_ids = {}
    for key, value in pairs(owned) do
        local id = type(value) == 'number' and value
            or (value and type(key) == 'number' and key or nil)
        if id and not seen_ids[id] then
            local item = res.key_items[id]
            if item and item.en then
                output[#output + 1] = {id = id, name = item.en}
                seen_ids[id] = true
            end
        end
    end
    table.sort(output, function(left, right) return left.name < right.name end)
    return output
end

local function send_telemetry(force)
    local name = player_name()
    if not name then return false end
    local items = windower.ffxi.get_items() or {}
    local sent = post_json('/api/telemetry', {
        character = name,
        gil = items.gil or 0,
        key_items = collect_key_items(),
        currencies = currencies,
    }, force)
    last_telemetry = os.time()
    return sent
end

local function request_currencies()
    pcall(function() packets.inject(packets.new('outgoing', 0x10F, {})) end)
    pcall(function() packets.inject(packets.new('outgoing', 0x115, {})) end)
    last_currency_request = os.time()
end

local function filtered_currency_packet(packet)
    local output = {}
    for name, amount in pairs(packet or {}) do
        if type(name) == 'string' and name:sub(1, 1) ~= '_' and type(amount) == 'number' then
            output[name] = amount
        end
    end
    return output
end

windower.register_event('load', function()
    load_cache()
    send_telemetry(true)
    coroutine.schedule(request_currencies, 1)
end)
windower.register_event('prerender', function()
    local now = os.clock()
    if now - last_scan >= 1 then
        last_scan = now
        scan_pool(false)
    end
    local wall_time = os.time()
    if wall_time - last_telemetry >= 60 then
        send_telemetry()
    end
    if wall_time - last_currency_request >= 300 then
        request_currencies()
    end
end)

windower.register_event('incoming chunk', function(id, original, modified)
    if id ~= 0x113 and id ~= 0x118 then return end
    local ok, packet = pcall(packets.parse, 'incoming', modified or original)
    if not ok or not packet then return end
    if id == 0x113 then
        currencies['1'] = filtered_currency_packet(packet)
    else
        currencies['2'] = filtered_currency_packet(packet)
    end
    coroutine.schedule(send_telemetry, 0.1)
end)

local function refresh_character_telemetry()
    coroutine.schedule(request_currencies, 1)
    coroutine.schedule(send_telemetry, 2)
end

windower.register_event('login', refresh_character_telemetry)
windower.register_event('zone change', refresh_character_telemetry)

windower.register_event('addon command', function(command, ...)
    command = command and command:lower() or 'help'
    if command == 'pool' then
        scan_pool(true)
    elseif command == 'reload' or command == 'refresh' then
        load_cache()
    elseif command == 'telemetry' then
        request_currencies()
        if send_telemetry(true) then
            windower.add_to_chat(158,
                '[LA] Character telemetry sent to InventoryCore.')
        else
            windower.add_to_chat(123,
                '[LA] Telemetry was not sent; InventoryCore remains unavailable.')
        end
    elseif command == 'item' then
        local query = table.concat({...}, ' '):lower()
        for id, item in pairs(res.items) do
            if item.en and item.en:lower() == query then show(id, true) return end
        end
        windower.add_to_chat(167, 'LootAdvisor: item not found: ' .. query)
    else
        windower.add_to_chat(207, 'LootAdvisor: //la pool | //la item <name> | //la reload | //la telemetry')
    end
end)
