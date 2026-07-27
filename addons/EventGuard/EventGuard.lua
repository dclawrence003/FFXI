_addon.name = 'EventGuard'
_addon.author = 'OpenAI Codex'
_addon.version = '1.0.0'
_addon.command = 'eventguard'
_addon.commands = {'eventguard', 'eg', 'unlock'}

require('strings')
require('coroutine')
local packets = require('packets')

local state_root = windower.windower_path .. 'addons\\EventGuard\\data\\'
local last_menu = nil
local last_self_update = nil
local last_self_status = nil

local function chat(color, message)
    windower.add_to_chat(color, '[EventGuard] ' .. message)
end

local function character_name()
    local player = windower.ffxi.get_player()
    return player and player.name or nil
end

local function state_path()
    local name = character_name()
    return name and (state_root .. name .. '.txt') or nil
end

local function save_menu()
    local path = state_path()
    if not path or not last_menu then
        return
    end

    local file = io.open(path, 'w')
    if not file then
        return
    end
    file:write(('%d|%d|%d|%d|%d'):format(
        last_menu.npc,
        last_menu.npc_index,
        last_menu.zone,
        last_menu.menu_id,
        os.time()))
    file:close()
end

local function load_menu()
    local path = state_path()
    if not path then
        return
    end

    local file = io.open(path, 'r')
    if not file then
        return
    end
    local value = file:read('*a')
    file:close()

    local npc, npc_index, zone, menu_id, recorded = value:match(
        '^(%d+)|(%d+)|(%d+)|(%d+)|(%d+)$')
    if npc then
        last_menu = {
            npc = tonumber(npc),
            npc_index = tonumber(npc_index),
            zone = tonumber(zone),
            menu_id = tonumber(menu_id),
            recorded = tonumber(recorded),
        }
    end
end

local function general_release()
    windower.packets.inject_incoming(
        0x052, string.char(0, 0, 0, 0, 0, 0, 0, 0))
    windower.packets.inject_incoming(
        0x052, string.char(0, 0, 0, 0, 1, 0, 0, 0))
end

local function release_recorded_menu()
    if not last_menu then
        chat(123, 'No recorded NPC menu is available.')
        return false
    end

    local current_zone = windower.ffxi.get_info().zone
    if last_menu.zone ~= current_zone then
        chat(123, ('Recorded menu belongs to zone %d; current zone is %d. '
            .. 'Refusing to send a stale server-side cancellation.'):format(
            last_menu.zone, current_zone))
        return false
    end

    local cancel = packets.new('outgoing', 0x05B, {
        ['Target'] = last_menu.npc,
        ['Option Index'] = 0,
        ['_unknown1'] = 16384,
        ['Target Index'] = last_menu.npc_index,
        ['Automated Message'] = false,
        ['_unknown2'] = 0,
        ['Zone'] = last_menu.zone,
        ['Menu ID'] = last_menu.menu_id,
    })
    packets.inject(cancel)

    windower.packets.inject_incoming(
        0x052, ('ICHC'):pack(0, 2, last_menu.menu_id, 0))
    general_release()
    chat(207, ('Sent cancel/release for NPC %d, index %d, menu %d.'):format(
        last_menu.npc, last_menu.npc_index, last_menu.menu_id))
    return true
end

local function force_local_idle()
    if not last_self_update then
        chat(123, 'No self-update packet has been observed since EventGuard loaded.')
        chat(123, 'Wait for a buff/status update, then run //eg status again.')
        return false
    end

    local update = packets.parse('incoming', last_self_update)
    if not update then
        chat(123, 'The saved self-update packet could not be parsed.')
        return false
    end

    local prior = update.Status
    update.Status = 0
    windower.packets.inject_incoming(0x037, packets.build(update))
    general_release()
    chat(207, ('Forced local status from %s to Idle (0).'):format(
        tostring(prior)))
    chat(123, 'If movement works but the server rejects actions, relog immediately.')
    return true
end

local function show_status()
    local player = windower.ffxi.get_player()
    local live_status = player and player.status or 'unknown'
    chat(207, ('FFXI status: %s; last observed self-update status: %s.'):format(
        tostring(live_status), tostring(last_self_status or 'none')))
    if last_menu then
        chat(207, ('Recorded NPC %d, index %d, zone %d, menu %d.'):format(
            last_menu.npc,
            last_menu.npc_index,
            last_menu.zone,
            last_menu.menu_id))
    else
        chat(207, 'No recorded NPC menu.')
    end
end

windower.register_event('incoming chunk', function(id, original, modified)
    if id == 0x032 or id == 0x034 then
        local menu = packets.parse('incoming', modified)
        if menu then
            last_menu = {
                npc = menu['NPC'],
                npc_index = menu['NPC Index'],
                zone = menu['Zone'],
                menu_id = menu['Menu ID'],
                recorded = os.time(),
            }
            save_menu()
        end
    elseif id == 0x037 then
        local update = packets.parse('incoming', modified)
        local player = windower.ffxi.get_player()
        if update and player and update.Player == player.id then
            last_self_update = modified
            last_self_status = update.Status
        end
    end
end)

windower.register_event('addon command', function(command, argument)
    command = command and command:lower() or 'status'
    argument = argument and argument:lower() or ''

    if command == 'status' or command == '' then
        show_status()
    elseif command == 'soft' then
        general_release()
        chat(207, 'Injected the standard local NPC-release sequence.')
    elseif command == 'menu' then
        release_recorded_menu()
    elseif command == 'local' then
        if argument ~= 'confirm' then
            chat(123, 'Local status repair requires: //eg local confirm')
            return
        end
        force_local_idle()
    elseif command == 'recover' then
        general_release()
        release_recorded_menu()
        chat(207, 'Soft and recorded-menu recovery completed.')
    else
        chat(207, 'Commands:')
        chat(207, '  //eg status        - show recorded recovery state')
        chat(207, '  //eg soft          - inject standard local releases')
        chat(207, '  //eg menu          - cancel the recorded NPC menu')
        chat(207, '  //eg recover       - run soft and menu recovery')
        chat(207, '  //eg local confirm - force stale local Event status to Idle')
    end
end)

windower.register_event('login', function()
    coroutine.schedule(load_menu, 3)
end)

coroutine.schedule(function()
    if windower.ffxi.get_player() then
        load_menu()
    end
end, 2)
