local BASE = 'addons/PartyTactics/'

local sandbox_loader, sandbox_error = loadfile(BASE..'lib/sandbox.lua')
assert(sandbox_loader, sandbox_error)
local sandbox = sandbox_loader()
local runtime_loader, runtime_error = sandbox.load(
    BASE..'profiles/vagary-direct-rancibus/runtime.lua', loadfile)
assert(runtime_loader, runtime_error)
local runtime_module = runtime_loader()

local IDS = {
    Dolomedes=1, Tackleberry=2, Kickpuncher=3,
    Barneystinson=4, Smalls=5, Achoo=6,
}

local function make_harness(options)
    options = options or {}
    local h = {
        now=0, zone=options.zone or 277, armed=false,
        player='Dolomedes', authority=nil,
        calls={}, alerts={}, tp={
            Dolomedes=options.dolo_tp or 0,
            Tackleberry=options.tackle_tp or 0,
            Kickpuncher=options.kick_tp or 0,
        },
    }
    h.boss = {
        id=900, index=1900, name=options.name or 'Rancibus',
        spawn_type=16, valid_target=true, hpp=nil,
        claim_id=options.foreign and 999999 or 0,
        claimed=false,
    }
    h.runtime = runtime_module.create()

    function h:record(call)
        call.at = self.now
        self.calls[#self.calls + 1] = call
    end
    function h:count(kind, fields)
        local count = 0
        for _, call in ipairs(self.calls) do
            local matches = call.kind == kind
            for key, value in pairs(fields or {}) do
                if call[key] ~= value then matches = false end
            end
            if matches then count = count + 1 end
        end
        return count
    end
    function h:claim()
        self.boss.claimed = true
        self.boss.claim_id = IDS.Dolomedes
    end

    h.context = {
        now=function() return h.now end,
        player_name=function() return h.player end,
        zone_id=function() return h.zone end,
        operator_armed=function() return h.armed end,
        current_target=function() return nil end,
        mob_array=function() return {h.boss} end,
        mob_by_id=function(id)
            if tonumber(id) == h.boss.id then return h.boss end
            return nil
        end,
        party_claimed=function(mob)
            return mob == h.boss and h.boss.claimed == true
        end,
        party_tp=function(name) return h.tp[name] end,
        authorize_encounter=function(id)
            h:record({kind='authorize', id=id})
            if options.authorization_fails then return false end
            h.authority = id
            return true
        end,
        release_encounter=function(id)
            h:record({kind='release', id=id})
            h.authority = nil
            return true
        end,
        monster_ability=function(id)
            local names = {
                [3372]='Cesspool', [3373]='Fetid Eddies',
                [3374]='Nullifying Rain', [3375]='Noyade',
                [3376]='Clobbering Wave', [691]='Manafont',
            }
            return names[tonumber(id)] and {en=names[tonumber(id)]} or nil
        end,
        job_ability=function() return nil end,
        spell=function(id)
            local names = {[359]='Silencega',[360]='Dispelga',[362]='Bindga'}
            return names[tonumber(id)] and {en=names[tonumber(id)]} or nil
        end,
        alert=function(message, audible)
            h.alerts[#h.alerts + 1] = {
                message=message, audible=audible, at=h.now,
            }
        end,
        client={
            engage_once=function(id)
                h:record({kind='engage-once', id=id})
                return options.engage_fails ~= true
            end,
        },
        actions={
            party_adapter=function(recipient, semantic, id, token)
                h:record({kind='controller', recipient=recipient,
                    semantic=semantic, id=id, token=token})
                if options.reject_semantic == semantic then return false end
                return true
            end,
            combat_force=function(id, exact_name)
                h:record({kind='force', id=id, exact_name=exact_name})
                return options.force_fails ~= true
            end,
            combat_stop=function()
                h:record({kind='stop'})
                return true
            end,
        },
    }

    function h:activate() self.runtime:on_activate(self.context) end
    function h:tick(at)
        self.now = at
        self.runtime:on_tick(self.context, at)
    end
    function h:action(packet, at)
        self.now = at
        self.runtime:on_action(self.context, packet)
    end
    return h
end

local tests = {}
local function test(name, callback)
    tests[#tests + 1] = {name=name, callback=callback}
end

test('profile load is inert until the operator arms', function()
    local h = make_harness()
    h:activate()
    h:tick(0)
    h:tick(10)
    assert(#h.calls == 0)
    assert(#h.alerts == 0)
end)

test('arm immediately starts independent preparation and one pull Flash', function()
    local h = make_harness({authorization_fails=true,
        reject_semantic='flash'})
    h:activate()
    h.armed = true
    h:tick(0)
    assert(h:count('controller', {
        recipient='Tackleberry', semantic='crusade'}) == 1)
    assert(h:count('controller', {
        recipient='Kickpuncher', semantic='no-foot-rise'}) == 1)
    assert(h:count('controller', {
        recipient='Barneystinson', semantic='barwatera-prepare'}) == 1)
    h:tick(1.25)
    h:tick(2.5)
    assert(h:count('controller', {
        recipient='Tackleberry', semantic='flash'}) == 1)
    h:tick(20)
    assert(h:count('controller', {
        recipient='Tackleberry', semantic='flash'}) == 1)
    assert(h:count('authorize', {id=h.boss.id}) == 1)
    assert(h:count('force') == 0 and h:count('engage-once') == 0)
    assert(#h.alerts == 0)
end)

test('failed Flash and authorization do not gate offense or support', function()
    local h = make_harness({authorization_fails=true,
        reject_semantic='flash', force_fails=true, engage_fails=true,
        dolo_tp=3000, tackle_tp=3000, kick_tp=3000})
    h:activate()
    h.armed = true
    h:tick(0)
    h:tick(1.25)
    h:tick(2.5)
    h:claim()
    h:tick(3.0)
    h:tick(4.3)

    assert(h:count('force', {id=h.boss.id, exact_name='Rancibus'}) == 1)
    assert(h:count('engage-once', {id=h.boss.id}) == 1)
    assert(h:count('controller', {
        recipient='Dolomedes', semantic='close'}) >= 1)
    assert(h:count('controller', {
        recipient='Tackleberry', semantic='middle'}) >= 1)
    assert(h:count('controller', {
        recipient='Kickpuncher', semantic='lead'}) >= 1)
    assert(h:count('controller', {
        recipient='Smalls', semantic='dia3'}) >= 1)
    assert(h:count('controller', {
        recipient='Achoo', semantic='geo-frailty'}) >= 1)
    assert(#h.alerts == 0)
end)

test('Dolo gets one local engage and shoots independently at low TP', function()
    local h = make_harness()
    h:activate()
    h.armed = true
    h:claim()
    h:tick(0)
    h:tick(4)
    h:tick(8)
    assert(h:count('engage-once', {id=h.boss.id}) == 1)
    assert(h:count('controller', {
        recipient='Dolomedes', semantic='shoot'}) >= 2)
    assert(h:count('controller', {
        recipient='Dolomedes', semantic='close'}) == 0)
end)

test('preclaim binding persists but postclaim loss expires', function()
    local h = make_harness()
    h:activate()
    h.armed = true

    h:tick(0)
    h:tick(30)
    assert(h:count('authorize', {id=h.boss.id}) == 1,
        'an unclaimed live Rancibus did not remain bound before the pull')
    assert(h:count('release', {id=h.boss.id}) == 0)

    h:claim()
    h:tick(30.3)
    h.boss.claimed = false
    h.boss.claim_id = 0
    h:tick(30.6)
    h:tick(32.1)
    assert(h:count('release', {id=h.boss.id}) == 0,
        'a transient postclaim gap released Rancibus too early')

    h:tick(32.6)
    assert(h:count('release', {id=h.boss.id}) == 1,
        'postclaim loss kept refreshing its own grace period')
    assert(h:count('stop') == 1)
end)

test('danger reactions add stuns without pausing damage lanes', function()
    local h = make_harness({dolo_tp=3000, tackle_tp=3000,
        kick_tp=3000})
    h:activate()
    h.armed = true
    h:claim()
    h:tick(0)
    h:action({category=7, actor_id=h.boss.id,
        targets={{id=IDS.Tackleberry,
            actions={{param=3374}}}}}, 10)
    h:tick(10.3)
    assert(h:count('controller', {
        recipient='Kickpuncher', semantic='stun'}) == 1)
    assert(h:count('controller', {
        recipient='Tackleberry', semantic='shield-bash'}) == 1)
    assert(h:count('controller', {recipient='Dolomedes', semantic='close'}) >= 2)
    assert(#h.alerts == 0)
end)

test('disarm cancels automation and stops PartyCombat', function()
    local h = make_harness()
    h:activate()
    h.armed = true
    h:claim()
    h:tick(0)
    h.armed = false
    h:tick(0.3)
    assert(h:count('controller', {semantic='cancel'}) == 6)
    assert(h:count('stop') == 1)
    assert(h:count('release', {id=h.boss.id}) == 1)
    local count = #h.calls
    h:tick(20)
    assert(#h.calls == count)
end)

for _, entry in ipairs(tests) do
    local ok, failure = pcall(entry.callback)
    if not ok then
        io.stderr:write('FAIL: '..entry.name..'\n'..tostring(failure)..'\n')
        os.exit(1)
    end
    io.write('PASS: '..entry.name..'\n')
end

io.write(('Rancibus runtime tests passed: %d\n'):format(#tests))
