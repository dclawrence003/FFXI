-- Passive integration harness: all game mutation APIs are absent and forbidden.
local unpack = unpack or table.unpack
local passed = 0
local function test(name, fn)
    local ok, err = pcall(fn)
    assert(ok, name .. ': ' .. tostring(err)); passed = passed + 1; print('PASS ' .. name)
end
local function harness(already_dead, missing_directory)
    local h = {now = 1800000000, events = {}, records = {}, marks = {}, notices = {}, packet_calls = {}}
    h.player = {id = 100, name = 'Smalls', status = already_dead and 2 or 0,
        main_job = 'RDM', sub_job = 'WHM', vitals = {hp = already_dead and 0 or 2200, hpp = already_dead and 0 or 100, mp = 1500, mpp = 100, tp = 0}, buffs = {43}}
    h.mobs = {
        [100] = {id = 100, index = 10, name = 'Smalls', status = h.player.status, hpp = h.player.vitals.hpp},
        [200] = {id = 200, index = 20, name = 'Tackleberry', status = 1, hpp = 100, target_index = 30},
        [300] = {id = 300, index = 30, name = 'Apollyon Demon', status = 1, hpp = 100, distance = 196},
        [400] = {id = 400, index = 40, name = 'Other Player', status = 0},
    }
    h.party = {p0 = {name = 'Smalls', hp = h.player.vitals.hp, hpp = h.player.vitals.hpp, mp = 1500, mob = h.mobs[100], zone = 38},
        p1 = {name = 'Tackleberry', hp = 3000, mp = 1300, mob = h.mobs[200], zone = 38}}
    h.info = {logged_in = true, zone = 38}
    local fake_store = {queued_bytes = 0, dropped = 0, write_errors = 0, last_write = h.now,
        directory = 'C:/mock/Smalls/', record = function(self, kind, data) h.records[#h.records + 1] = {kind = kind, data = data} end,
        mark = function(self, reason, data) h.marks[#h.marks + 1] = {reason = reason, data = data}; self.incident = true end,
        tick = function(self) self.last_write = h.now end, close = function(self) h.closed = true end}
    local res = {spells = {[1] = {en = 'Cure', recast_id = 1}, [6] = {en = 'Cure III', recast_id = 6},
            [59] = {en = 'Silence', recast_id = 59}},
        job_abilities = {[83] = {en = 'Convert', recast_id = 49}}, weapon_skills = {}, monster_abilities = {},
        buffs = {[43] = {en = 'Refresh'}}, zones = {[38] = {en = 'Apollyon'}},
        action_messages = {[1] = {en = '${actor} hits ${target} for ${number} points of damage.'},
            [6] = {en = '${actor} defeats ${target}.'}}}
    local function forbidden(_, key) error('FORBIDDEN/nonexistent game API: ' .. tostring(key)) end
    local ffxi = setmetatable({get_player = function() return h.player end, get_info = function() return h.info end,
        get_party = function() return h.party end, get_mob_by_id = function(id) return h.mobs[id] end,
        get_mob_by_index = function(index) for _, mob in pairs(h.mobs) do if mob.index == index then return mob end end end,
        get_mob_by_target = function(target) return target == 'me' and h.mobs[100] or nil end,
        get_spell_recasts = function() return {[1] = 180, [59] = 0} end,
        get_ability_recasts = function() return {[49] = 30} end}, {__index = forbidden})
    local windower = setmetatable({ffxi = ffxi, addon_path = 'addons/CombatRecorder/',
        packets = setmetatable({parse_action = function(data)
            h.packet_calls[#h.packet_calls + 1] = data
            if h.parse_error then error('bad packet') end
            return h.action
        end}, {__index = forbidden}),
        register_event = function(event, fn) h.events[event] = fn end,
        add_to_chat = function(mode, text) h.notices[#h.notices + 1] = text end,
        dir_exists = function() return not missing_directory end, file_exists = function() return false end,
        get_dir = function() return {} end}, {__index = forbidden})
    local env = setmetatable({_addon = {}, windower = windower,
        os = {time = function() return h.now end, clock = function() return h.now / 100 end,
            getenv = function() return 'C:/mock' end, remove = function() error('unexpected file removal') end},
        require = function(name) assert(name == 'resources'); return res end,
        loadfile = function(path)
            if path:find('recorder.lua', 1, true) then return function() return {new = function() return fake_store end} end end
            return loadfile(path)
        end}, {__index = _G})
    local path = 'addons/CombatRecorder/CombatRecorder.lua'
    if setfenv then setfenv(assert(loadfile(path)), env)()
    else assert(loadfile(path, 't', env))() end
    function h:fire(event, ...) assert(self.events[event], 'event missing ' .. event); assert(self.events[event](...) == nil) end
    function h:count(kind) local n = 0; for _, r in ipairs(self.records) do if r.kind == kind then n = n + 1 end end; return n end
    function h:last(kind) for i = #self.records, 1, -1 do if self.records[i].kind == kind then return self.records[i].data end end end
    return h
end
local function packet(fields)
    local bytes = {}; for i = 1, 28 do bytes[i] = 0 end
    for _, f in ipairs(fields) do
        local value = f[2]
        for i = 1, f[3] do bytes[f[1] + i] = value % 256; value = math.floor(value / 256) end
    end
    return string.char(unpack(bytes))
end

test('startup captures state and recasts without mutation APIs', function()
    local h = harness()
    assert(h:count('session_start') == 1 and h:count('snapshot') == 1)
    assert(h:last('snapshot').puller_target.name == 'Apollyon Demon')
    assert(h:last('recasts').spells_seconds.Cure == 3 and h:last('recasts').abilities_seconds.Convert == 30)
    assert(h:count('recorder_error') == 0)
end)
test('loading already dead does not invent a death', function()
    local h = harness(true); h:fire('prerender'); assert(#h.marks == 0 and h:count('death') == 0)
end)
test('missing pre-created directory fails inertly without creation', function()
    local h = harness(false, true)
    assert(h:count('session_start') == 0 and #h.marks == 0)
    assert(table.concat(h.notices, '\n'):find('pre%-created data directory is missing'))
end)
test('raw original action survives display filtering and modification', function()
    local h = harness()
    h.action = {actor_id = 300, category = 1, param = 0,
        targets = {{id = 100, actions = {{message = 1, param = 351, reaction = 8}}}}}
    h:fire('incoming chunk', 0x028, 'raw-server-packet', 'battlemod-modified', false, true)
    assert(h.packet_calls[1] == 'raw-server-packet' and h:last('action').blocked_for_display)
    assert(h:last('action').targets[1].actions[1].param == 351)
    h:fire('incoming chunk', 0x028, 'injected', 'injected', true, false)
    assert(h:count('action') == 1)
end)
test('outgoing request uses modified packet and labels blocked attempts', function()
    local h = harness()
    local original = packet({{4, 300, 4}, {8, 30, 2}, {10, 3, 2}, {12, 59, 2}})
    local modified = packet({{4, 200, 4}, {8, 20, 2}, {10, 3, 2}, {12, 6, 2}})
    h:fire('outgoing chunk', 0x01A, original, modified, true, true)
    local request = h:last('action_request')
    assert(request.name == 'Cure III' and request.target.name == 'Tackleberry' and request.blocked and request.modified)
end)
test('party action-message death archives once despite duplicate status', function()
    local h = harness()
    local raw = packet({{4, 300, 4}, {8, 100, 4}, {12, 500, 4}, {24, 6 + 32768, 2}})
    h:fire('incoming chunk', 0x029, raw, raw, false, true)
    h:fire('hp change', 0, 500); h:fire('status change', 2, 1)
    assert(#h.marks == 1 and h:count('death') == 1 and h:last('action_message').message == 6)
end)
test('revival permits a genuinely new death', function()
    local h = harness()
    h:fire('status change', 2, 1); h:fire('hp change', 500, 0); h:fire('status change', 2, 1)
    assert(#h.marks == 2)
end)
test('transient zero HP during zoning is not proof of death', function()
    local h = harness()
    h:fire('hp change', 0, 2200); assert(#h.marks == 0)
end)
test('another party member dying is recorded from snapshot', function()
    local h = harness()
    h.party.p1.hp = 0; h.mobs[200].status = 2; h.now = h.now + 11
    h:fire('prerender')
    assert(h:last('death').victim.name == 'Tackleberry')
end)
test('ordinary/private chat and unrelated IPC are ignored', function()
    local h = harness()
    h:fire('incoming text', 'Alice>> private message', '', 12)
    h:fire('incoming text', '[PartyStart PLD] test in party chat', '', 13)
    h:fire('incoming text', '[PartyStart PLD] Cure IV -> Smalls', '', 207)
    h:fire('ipc message', 'unrelated|sensitive-content')
    h:fire('ipc message', 'PARTYCOMBAT1|stop|Dolomedes')
    assert(h:count('diagnostic') == 1 and h:count('automation_observed') == 1)
    assert(not h.events['chat message'] and not h.events['outgoing text'])
end)
test('malformed packets cannot escape callback or block combat', function()
    local h = harness(); h.parse_error = true
    h:fire('incoming chunk', 0x028, 'broken', 'broken', false, false)
    h:fire('incoming chunk', 0x029, 'short', 'short', false, false)
    assert(h:count('recorder_error') == 1)
end)
test('HP max changes and buffs are separate from damage evidence', function()
    local h = harness()
    h:fire('hpmax change', 2300, 2200); h:fire('hp change', 2100, 2200); h:fire('lose buff', 43)
    assert(h:count('vital_change') == 2 and h:last('buff').name == 'Refresh' and #h.marks == 0)
end)
test('zone, status, marker and unload remain passive', function()
    local h = harness()
    h:fire('zone change', 37, 38); h.info.zone = 37; h:fire('prerender')
    h:fire('addon command', 'status'); h:fire('addon command', 'mark', 'test')
    h:fire('unload'); assert(h.closed and #h.marks == 1 and h:count('recorder_error') == 0)
end)
print(string.format('%d addon integration tests passed', passed))
