-- Execute the actual addon with in-memory files, packets, and HTTP. No game,
-- live history, or InventoryCore database is touched by this harness.
local addon_path = LIMBUS_TRACKER_UNDER_TEST or 'addons/LimbusTracker/LimbusTracker.lua'

local function session(existing_files, zone, character)
    character = character or 'Dolomedes'
    local test = {files=existing_files or {}, callbacks={}, posts={}, chats={}, now=1000,
        zone=zone or 38, packet_id=0, packets={}, scheduled={}, http_status=200}
    test.history_path = 'mock/data\\history_'..character..'.lua'
    local display = {}
    function display:text(value) test.display = value end
    function display:show() end
    function display:hide() end
    function display:pos() return 20, 250 end
    local modules = {
        config={load=function(_, defaults)
            defaults.save = function() end
            return defaults
        end},
        texts={new=function() return display end},
        packets={
            parse=function(_, raw) return test.packets[raw] end,
            new=function(_, id) return {id=id} end,
            inject=function() end,
        },
        ['socket.http']={request=function(request)
            if test.http_status == 200 then
                test.posts[#test.posts + 1] = request.source()
            end
            return 1, test.http_status
        end},
        ltn12={
            source={string=function(value) return function() return value end end},
            sink={table=function() return function() return 1 end end},
        },
    }
    local env = setmetatable({
        _addon={},
        require=function(name) return assert(modules[name], name) end,
        os={
            time=function() return test.now end,
            remove=function(path) test.files[path] = nil; return true end,
            rename=function(from, to)
                if not test.files[from] then return nil, 'missing mock file' end
                test.files[to], test.files[from] = test.files[from], nil
                return true
            end,
        },
        io={open=function(path, mode)
            assert(mode == 'w', 'unexpected file read/write mode')
            local chunks = {}
            return {
                write=function(_, ...)
                    for _, value in ipairs({...}) do chunks[#chunks + 1] = tostring(value) end
                end,
                close=function() test.files[path] = table.concat(chunks) end,
            }
        end},
        dofile=function(path) return assert((loadstring or load)(assert(test.files[path], path)))() end,
        coroutine={schedule=function(callback, delay)
            test.scheduled[#test.scheduled + 1] = {callback=callback, delay=delay}
        end},
        windower={
            addon_path='mock/',
            ffxi={
                get_player=function() return {name=character} end,
                get_info=function() return {zone=test.zone} end,
            },
            dir_exists=function() return true end,
            create_dir=function() error('unexpected directory creation') end,
            add_to_chat=function(_, message) test.chats[#test.chats + 1] = message end,
            register_event=function(name, callback) test.callbacks[name] = callback end,
        },
    }, {__index=_G})
    if setfenv then setfenv(assert(loadfile(addon_path)), env)()
    else assert(loadfile(addon_path, 't', env))() end
    test.callbacks.load()
    function test:state()
        return assert((loadstring or load)(assert(self.files[self.history_path])))()
    end
    function test:packet(direction, id, fields, modified_fields)
        self.packet_id = self.packet_id + 1
        local raw = 'packet_'..self.packet_id
        self.packets[raw] = fields
        local modified = raw
        if modified_fields then
            modified = raw..'_modified'
            self.packets[modified] = modified_fields
        end
        self.callbacks[direction..' chunk'](id, raw, modified)
    end
    function test:units(apollyon, temenos)
        self:packet('incoming', 0x118, {
            ['Apollyon Units']=apollyon, ['Temenos Units']=temenos or 54830,
        })
    end
    function test:begin(target)
        self:packet('outgoing', 0x01A, {Target=target or 16933566, Category=0})
    end
    function test:reward(area, amount, modified, blocked)
        local original = 'Acquired '..area..' Units: '..tostring(amount)
        assert(self.callbacks['incoming text'], 'missing direct acquisition-message listener')
        return self.callbacks['incoming text'](original, modified or original, 121, 121, blocked)
    end
    return test
end

-- Dolo's North miss: Code 2,170 + coffer 3,000 arrive in one balance snapshot.
-- The coffer receipt, not the combined 5,170 difference, identifies its reward.
local north = session(nil, 37)
north:units(17612, 54830)
north:begin(16929000)
north:reward('Temenos', 2170)
north:begin(16929362)
north:packet('incoming', 0x034, {NPC=16929362, Zone=37})
north:units(17612, 60000)
north:reward('Temenos', 3000)
local north_event = north:state().events.Temenos[1]
assert(north_event and north_event.chest == 'North' and north_event.units == 3000,
    'combined Code/coffer snapshot lost North or misclassified it as a bonus')
assert(#north:state().events.Temenos == 1 and #north.posts == 1,
    'Code receipt or repeated snapshot created extra history')

-- Tackleberry's live North receipt on 2026-08-30. FFXI's 0x07 separates
-- visible lines inside ONE incoming-text message, not separate callbacks.
local tackle_receipt = session(nil, 37, 'Tackleberry')
tackle_receipt:units(12612, 54550)
tackle_receipt:begin(16929362)
tackle_receipt:packet('incoming', 0x034, {NPC=16929362, Zone=37})
tackle_receipt:units(12612, 57550)
tackle_receipt.callbacks['incoming text'](
    'Acquired Temenos Units: 3000.\7Remaining Temenos Units: 134000.\7Total Temenos Units: 57550/60000.',
    '', 121, 121, false)
local tackle_event = tackle_receipt:state().events.Temenos[1]
assert(tackle_event and tackle_event.chest == 'North' and tackle_event.units == 3000,
    'multi-line Acquired/Remaining/Total receipt was rejected as a whole string')
assert(tackle_receipt.posts[1]:find('"character":"Tackleberry"', 1, true),
    'Tackleberry receipt was mirrored under another character')

for _, separator in ipairs({'\7', '\n', '\r\n'}) do
    for _, area in ipairs({{name='Temenos', zone=37, target=16929362},
        {name='Apollyon', zone=38, target=16933566}}) do
        for _, units in ipairs({3000,4170,5000}) do
            local test = session(nil, area.zone)
            test:begin(area.target)
            local original = 'Lost temporary item: '..area.name..' code.'..separator
                ..'Acquired \31\7'..area.name..'\30\1 Units: '..units..'.'..separator
                ..'Remaining '..area.name..' Units: 134000.'..separator
                ..'Total '..area.name..' Units: 57550/60000.\127\49'
            test.callbacks['incoming text'](original, '[reformatted]', 150, 121, true)
            local event = test:state().events[area.name][1]
            assert(event and event.units == units and #test.posts == 1,
                'line boundaries, surrounding lines, or color argument 0x07 lost the receipt')
            local seen = false
            for _, observation in ipairs(test:state().runtime.observations) do
                if observation.kind == 'unit-text' then
                    seen = observation.parsed_units == units and observation.raw_hex ==
                        original:gsub('.', function(byte) return ('%02X'):format(byte:byte()) end)
                end
            end
            assert(seen, 'exact original unit-message bytes were not retained')
            test.callbacks['incoming text'](original, '', 150, 121, true)
            assert(#test:state().events[area.name] == 1 and #test.posts == 1,
                'multi-line receipt duplicated the opening')
        end
    end
end

local unparsed = session(nil, 37)
unparsed:begin(16929362)
unparsed.callbacks['incoming text']('Remaining Temenos Units: 3000.\7Total Temenos Units: 5000/60000.',
    '', 150, 150, false)
assert(#unparsed:state().events.Temenos == 0, 'Remaining/Total values were mistaken for acquired units')
local rejected_text = unparsed:state().runtime.observations[2]
assert(rejected_text.kind == 'unit-text' and rejected_text.raw_hex and not rejected_text.parsed_area,
    'rejected unit-message bytes disappeared from the diagnostics')

-- Dolo's earlier SE failure: the separate 84 must not label the coffer or
-- prevent its actual 5,000-unit receipt from being recorded.
local se = session()
se:units(12420)
se:begin()
se:units(12504)
se:reward('Apollyon', 84)
assert(#se:state().events.Apollyon == 0, '84 units became a chest')
assert(se:state().runtime.pending_chest.units_before == 12420,
    'diagnostic starting balance was replaced by a later snapshot')
se:packet('incoming', 0x034, {NPC=16933566, Zone=38})
se:packet('outgoing', 0x05B, {Target=16933566, Zone=38})
se:units(17504)
se:reward('Apollyon', 5000)
local events = se:state().events.Apollyon
assert(#events == 1 and events[1].chest == 'SE' and events[1].units == 5000,
    'SE bonus was lost by adding the earlier 84 units')
assert(events[1].confirmation == 'acquisition-message', 'receipt evidence was not saved')
assert(events[1].synced and #se.posts == 1, 'confirmed opening was not mirrored')
assert(se.display:find('Bonus: SE', 1, true), 'in-game bonus display did not update')
se:units(17504)
se:packet('outgoing', 0x05B, {Target=16933566, Zone=38, ['Automated Message']=true})
se:units(17504)
se:reward('Apollyon', 5000)
assert(#se:state().events.Apollyon == 1 and #se.posts == 1, 'repeated stages duplicated the opening')

-- Currency corrections/spending do not gate the next actual coffer receipt.
for _, balances in ipairs({{10000,10084,13084,3000}, {49326,9494,12494,3000}}) do
    local test = session()
    test:units(balances[1])
    test:begin(16933563)
    test:units(balances[2])
    test:units(balances[3])
    test:reward('Apollyon', balances[4])
    local event = test:state().events.Apollyon[1]
    assert(event and event.units == balances[4], 'updated/spent balance broke the next exact reward')
end

-- Every authoritative final target works, including capped bonus amounts.
for _, area in ipairs({
    {zone=37, name='Temenos', targets={16929362,16929363,16929364,16929365}},
    {zone=38, name='Apollyon', targets={16933563,16933564,16933565,16933566}},
}) do
    for _, target in ipairs(area.targets) do
        for _, amount in ipairs({3000,4000,5000}) do
            local test = session(nil, area.zone)
            test:units(10000,10000)
            test:begin(target)
            test:units(area.zone == 38 and 10000 + amount or 10000,
                area.zone == 37 and 10000 + amount or 10000)
            test:reward(area.name, amount)
            local event = test:state().events[area.name][1]
            assert(event and event.target_id == target and event.units == amount,
                'authoritative final target lost receipt detection')
        end
    end
end

-- No rounding or loose thresholds: 5,084 in ONE unseparated update is ambiguous.
local combined = session()
combined:units(12420)
combined:begin()
combined:units(17504)
assert(#combined:state().events.Apollyon == 0, 'ambiguous combined gain was rounded into a bonus')
local unknown = session()
unknown:units(10000)
unknown:begin(16933000)
unknown:units(13000)
unknown:reward('Apollyon', 3000)
assert(#unknown:state().events.Apollyon == 0, 'unrecognized NPC/Code reward created history')

-- Clicking another object abandons an unclaimed coffer. A Code's subsequent
-- 3,000 units must never satisfy the old request, regardless of which packet
-- stage exposes the new object (ordinary, injected, or mirrored interaction).
for _, area in ipairs({
    {zone=37, name='Temenos', target=16929364},
    {zone=38, name='Apollyon', target=16933566},
}) do
    for _, stage in ipairs({
        {direction='outgoing', id=0x01A, fields={Target=16933000, Category=0}},
        {direction='outgoing', id=0x05B, fields={Target=16933000, Zone=area.zone}},
        {direction='incoming', id=0x032, fields={NPC=16933000, Zone=area.zone}},
        {direction='incoming', id=0x034, fields={NPC=16933000, Zone=area.zone}},
    }) do
        local test = session(nil, area.zone)
        test:units(10000,10000)
        test:begin(area.target)
        assert(test:state().runtime.pending_chest, 'missing test coffer observation')
        test:packet(stage.direction, stage.id, stage.fields)
        assert(test:state().runtime.pending_chest == nil,
            'different object did not clear and persist the old coffer request')
        test:units(area.zone == 38 and 13000 or 10000,
            area.zone == 37 and 13000 or 10000)
        test:reward(area.name, 3000)
        assert(#test:state().events[area.name] == 0 and #test.posts == 0,
            'Code reward was credited to the abandoned coffer')
        local restored = session(test.files, area.zone)
        restored:units(area.zone == 38 and 13000 or 10000,
            area.zone == 37 and 13000 or 10000)
        assert(restored:state().runtime.pending_chest == nil,
            'reload resurrected an abandoned coffer')
        restored:begin(area.target)
        restored:units(area.zone == 38 and 16000 or 10000,
            area.zone == 37 and 16000 or 10000)
        restored:reward(area.name, 3000)
        assert(#restored:state().events[area.name] == 1,
            'abandoning a coffer disabled a later legitimate opening')
    end
end

-- A valid original packet for another NPC wins over a modified coffer target.
local original_npc = session()
original_npc:units(10000)
original_npc:begin()
original_npc:packet('outgoing', 0x01A, {Target=16933000, Category=0},
    {Target=16933566, Category=0})
original_npc:units(13000)
original_npc:reward('Apollyon', 3000)
assert(#original_npc:state().events.Apollyon == 0,
    'modified packet overrode the original different-object interaction')

-- Combat actions and malformed target-less packets are not NPC interactions.
local other_actions = session()
other_actions:units(10000)
other_actions:begin()
other_actions:packet('outgoing', 0x01A, {Target=16933000, Category=3},
    {Target=16933000, Category=0})
other_actions:packet('outgoing', 0x01A, {Target=0, Category=0})
other_actions:packet('incoming', 0x034, {NPC=0})
assert(other_actions:state().runtime.pending_chest,
    'combat or malformed packet incorrectly abandoned the coffer')
other_actions:units(15000)
other_actions:reward('Apollyon', 5000)
assert(#other_actions:state().events.Apollyon == 1,
    'legitimate coffer was lost after a non-interaction action')

local different_coffer = session()
different_coffer:units(10000)
different_coffer:begin(16933566)
different_coffer:begin(16933563)
different_coffer:units(13000)
different_coffer:reward('Apollyon', 3000)
local switched_event = different_coffer:state().events.Apollyon[1]
assert(switched_event and switched_event.chest == 'NW',
    'switching final coffers credited the earlier target')

local no_baseline = session()
no_baseline:begin()
no_baseline:units(10000)
assert(#no_baseline:state().events.Apollyon == 0, 'first balance invented an earlier reward')
no_baseline:units(15000)
assert(#no_baseline:state().events.Apollyon == 0, 'balance-only gain invented a chest')
no_baseline:reward('Apollyon', 5000)
assert(#no_baseline:state().events.Apollyon == 1, 'receipt required an older baseline')

-- A reload keeps the pending coffer; its receipt needs no balance correlation.
local reload = session()
reload:units(12420)
reload:begin()
reload:units(12504)
local restored = session(reload.files)
restored:units(17504)
restored:reward('Apollyon', 5000)
assert(#restored:state().events.Apollyon == 1, 'reload lost the pending coffer')
local expired = session()
expired:units(10000)
expired:begin()
expired.now = expired.now + 121
expired:units(15000)
expired:reward('Apollyon', 5000)
assert(#expired:state().events.Apollyon == 0, 'expired coffer captured an unrelated later gain')

-- A backend outage must not prevent standalone recording; later sync is one-shot.
local offline = session()
offline.http_status = 503
offline:units(10000)
offline:begin()
offline:units(15000)
offline:reward('Apollyon', 5000)
assert(#offline:state().events.Apollyon == 1 and not offline:state().events.Apollyon[1].synced,
    'InventoryCore outage lost the standalone opening')
offline.http_status = 200
offline.callbacks['addon command']('sync', 'now')
offline.callbacks['addon command']('sync', 'now')
assert(#offline.posts == 1 and offline:state().events.Apollyon[1].synced,
    'optional sync did not recover exactly once')

-- Balance ordering is irrelevant: no snapshot, stale snapshot, negative
-- spending correction, already-paid snapshot, and misleading exact 5,000.
for _, balance in ipairs({false, 10000, 500, 13000, 15000}) do
    local test = session(nil, 37)
    test:units(10000, 10000)
    test:begin(16929362)
    if balance then test:units(10000, balance) end
    assert(#test:state().events.Temenos == 0, 'snapshot guessed a reward before its receipt')
    test:reward('Temenos', 3000)
    test:units(10000, 13000)
    local event = test:state().events.Temenos[1]
    assert(event and event.units == 3000 and #test.posts == 1,
        'currency order changed the coffer receipt')
    assert(test.display:find('Bonus: --', 1, true), 'combined balance became a false bonus')
end
local never_polled = session()
never_polled:begin()
never_polled:reward('Apollyon', 5000)
assert(#never_polled:state().events.Apollyon == 1, 'no currency packet blocked the receipt')

-- Each observed interaction stage alone can establish the known final target.
for _, stage in ipairs({
    {direction='outgoing', id=0x01A, fields={Target=16933566, Category=0}},
    {direction='outgoing', id=0x05B, fields={Target=16933566, Zone=38}},
    {direction='incoming', id=0x032, fields={NPC=16933566, Zone=38}},
    {direction='incoming', id=0x034, fields={NPC=16933566, Zone=38}},
}) do
    local test = session()
    test:packet(stage.direction, stage.id, stage.fields)
    test:reward('Apollyon', 3000)
    assert(#test:state().events.Apollyon == 1, 'an interaction stage could not pair with the receipt')
end

-- Use untouched personal system text, including FFXI controls, comma-formatted
-- amounts and hidden/recolored copies. Never rewrite or unblock the chat log.
local colored = session()
colored:begin()
local result = colored.callbacks['incoming text'](
    '\30\01Acquired Apollyon Units: \31\1585,000\30\01.\127\49',
    '[hidden by another addon]', 121, 123, true)
assert(result == nil and colored:state().events.Apollyon[1].units == 5000,
    'original acquisition line was hidden or modified by another addon')
for _, invalid in ipairs({
    'Smalls: Acquired Apollyon Units: 5000',
    'You have 5000 Apollyon Units.',
    'Acquired Unknown Units: 5000',
    'Acquired Apollyon Units: 30000',
    'Acquired Apollyon Units: 5000.5',
    'Acquired Apollyon Units: -3000',
}) do
    local test = session()
    test:begin()
    test.callbacks['incoming text'](invalid, 'Acquired Apollyon Units: 5000', 121, 121, false)
    assert(#test:state().events.Apollyon == 0, 'non-receipt or modified text created an opening')
end
local wrong_area = session()
wrong_area:begin()
wrong_area:reward('Temenos', 5000)
assert(#wrong_area:state().events.Apollyon == 0, 'other area receipt opened the pending coffer')
wrong_area:reward('Apollyon', 3000)
assert(#wrong_area:state().events.Apollyon == 1, 'other area receipt destroyed the valid pending coffer')

-- Repeated timestamps/reloads and receipt-before-final-dialog ordering must
-- still yield one durable opening and one optional backend submission.
local after_reward = session(north.files, 37)
after_reward:packet('outgoing', 0x05B, {Target=16929362, Zone=37, ['Automated Message']=true})
after_reward:reward('Temenos', 3000)
assert(#after_reward:state().events.Temenos == 1 and #after_reward.posts == 0,
    'reload/final dialog duplicated the already saved receipt')

-- The local diagnostic trail is bounded and contains only structured Limbus
-- observations, not general chat or a growing packet log.
local bounded = session()
for _ = 1, 70 do
    bounded:begin(16933000)
    bounded:reward('Apollyon', 3000)
end
local observations = bounded:state().runtime.observations
assert(#observations == 48 and observations[48].reason == 'no-final-coffer',
    'diagnostics were unbounded or failed to explain why a Code was ignored')
bounded.callbacks['incoming text']('A private unrelated message', '', 3, 3, false)
assert(#bounded:state().runtime.observations == 48, 'unrelated chat entered diagnostics')

print('LimbusTracker acquisition receipts, Code exclusion, balance ordering, persistence, and sync OK')
