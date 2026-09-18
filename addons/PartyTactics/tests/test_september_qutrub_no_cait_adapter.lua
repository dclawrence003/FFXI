-- Behavioral tests for the no-Cait Qutrub manual-pass-through adapter.

local source = debug.getinfo(1, 'S').source:gsub('^@', '')
local test_dir = source:match('^(.*)[/\\][^/\\]+$') or '.'
local adapter_path = arg and arg[1]
    or (test_dir..'/../gearswap/adapters/'
        ..'ambuscade-2026-09-v1-qutrub-bigwig-no-cait/1.10.0.lua')

local NAMES = {
    'Dolomedes','Tackleberry','Kickpuncher',
    'Barneystinson','Smalls','Achoo',
}

local function new_world(job, options)
    options = options or {}
    local clock = 100
    local inputs, commands = {}, {}
    local player_name = options.player_name or 'Dolomedes'
    local player_id = options.player_id
    if not player_id then
        for index, name in ipairs(NAMES) do
            if name == player_name then player_id = 1000 + index end
        end
    end
    player_id = player_id or 1001
    local max_mp = options.max_mp or 1000
    local mpp = options.mpp or 100
    local player = {
        id=player_id, name=player_name,
        main_job=job, status='Engaged', buffs=options.buffs or {},
        hpp=options.hpp or 100, mpp=mpp,
        mp=options.mp or max_mp * mpp / 100, max_mp=max_mp,
        in_combat=options.in_combat == nil and true or options.in_combat,
        tp=options.tp == nil and 1000 or options.tp,
    }
    local mobs = {}
    local boss = {
        id=17990001, index=411, name='Bozzetto Bigwig',
        claim_id=1001, spawn_type=16, valid_target=true, hpp=100,
        x=0, y=0,
    }
    local astrologer = {
        id=17990002, index=412, name='Bozzetto Astrologer',
        claim_id=1001, spawn_type=16, valid_target=true, hpp=100,
        x=30, y=0,
    }
    local tormentor = {
        id=17990003, index=413, name='Bozzetto Tormentor',
        claim_id=1001, spawn_type=16, valid_target=true, hpp=100,
        x=31, y=0,
    }
    mobs[boss.id], mobs[astrologer.id], mobs[tormentor.id] =
        boss, astrologer, tormentor

    local party = {}
    for index, name in ipairs(NAMES) do
        local id = 1000 + index
        party['p'..tostring(index - 1)] = {
            name=name, hpp=100, mob={id=id},
        }
        mobs[id] = {
            id=id, index=id, name=name, valid_target=true, hpp=100,
            x=id == player.id and 30 or 2, y=0, distance=4,
        }
    end

    local inventory = {max=80, count=0}
    for index, item in ipairs(options.items or {}) do
        inventory[index] = type(item) == 'table' and item
            or {id=item, count=1}
        inventory.count = inventory.count + 1
    end

    local env = setmetatable({}, {__index=_G})
    env._G = env
    env.os = setmetatable({clock=function() return clock end}, {__index=os})
    env.player = player
    env.moving = options.moving or false
    env.tickdelay = options.tickdelay or 0
    env.midaction = function() return options.midaction == true end
    env.silent_check_disable = function()
        return options.automation_disabled == true
    end
    env.silent_can_use = function(id)
        return options.usable_spells == nil
            or options.usable_spells[tonumber(id)] == true
    end
    local learned_spells = options.learned_spells or {}
    if options.learned_spells == nil then
        for id=1,600 do learned_spells[id] = true end
    end
    env.windower = {
        chat={input=function(command) inputs[#inputs + 1] = command end},
        send_command=function(command) commands[#commands + 1] = command end,
        ffxi={
            get_player=function() return player end,
            get_info=function()
                return {logged_in=true, zone=options.zone or 287}
            end,
            get_mob_by_id=function(id) return mobs[tonumber(id)] end,
            get_party=function() return party end,
            get_items=function(bag)
                if bag == 0 or bag == 'inventory' then return inventory end
                return nil
            end,
            get_spell_recasts=function()
                return options.spell_recasts or {[338]=0,[339]=0}
            end,
            get_spells=function() return learned_spells end,
            get_ability_recasts=function()
                return options.ability_recasts or {[220]=0,[221]=0}
            end,
        },
    }

    local loader, load_error
    if setfenv then
        loader, load_error = loadfile(adapter_path)
        if loader then setfenv(loader, env) end
    else
        loader, load_error = loadfile(adapter_path, 't', env)
    end
    assert(loader, load_error)
    local adapter = loader()
    assert(adapter.activate() == true)

    local world = {
        adapter=adapter, env=env, player=player, mobs=mobs,
        boss=boss, astrologer=astrologer, tormentor=tormentor,
        party=party, inputs=inputs, commands=commands,
    }
    function world:advance(seconds) clock = clock + seconds end
    function world:set_mpp(mpp)
        self.player.mpp = mpp
        self.player.mp = self.player.max_mp * mpp / 100
    end
    function world:set_hpp(name, hpp)
        for _, member in pairs(self.party) do
            if member.name == name then member.hpp = hpp end
        end
        for _, mob in pairs(self.mobs) do
            if mob.name == name then mob.hpp = hpp end
        end
        if self.player.name == name then self.player.hpp = hpp end
    end
    function world:action(semantic, subject)
        local arguments = {
            tostring(self.boss.id), '1700000000-1001-1', '0',
        }
        if subject then
            arguments[4] = '-'
            arguments[5] = tostring(type(subject) == 'table'
                and subject.id or subject)
        end
        return self.adapter.handle_action(
            'qutrub-bigwig-no-cait', semantic, arguments)
    end
    function world:aftercast(id, name, interrupted)
        self.adapter.job_aftercast({
            id=id, english=name, interrupted=interrupted == true,
        }, nil, {})
    end
    return world
end

local metadata = new_world('COR')
assert(metadata.adapter.id
    == 'ambuscade-2026-09-v1-qutrub-bigwig-no-cait')
assert(metadata.adapter.version == '1.10.0')
assert(metadata.adapter.controller == 'qutrub-bigwig-no-cait')
assert(metadata.adapter.protocol == 1)

-- Ordinary actions do not require a probe, preflight, buff, or prior result.
local cor = new_world('COR')
assert(cor:action('pull', cor.boss) == true)
assert(cor.inputs[1] == '/ja "Light Shot" 17990001')
cor:advance(1)
assert(cor:action('light-shot-target', cor.astrologer) == true)
assert(cor.inputs[2] == '/ja "Light Shot" 17990002')
cor:advance(1)
assert(cor:action('close', cor.boss) == false)
assert(#cor.inputs == 2, 'adapter must not own weaponskills')

-- No automatic submission ever owns the manual GearSwap callbacks.
local manual = {id=999, english='Savage Blade', action_type='Weaponskill'}
assert(cor.adapter.filter_pretarget(manual, nil, {}) == false)
assert(cor.adapter.filter_precast(manual, nil, {}) == false)
assert(cor:action('food') == true)
assert(cor.adapter.filter_precast(manual, nil, {}) == false)

-- Duplicate semantic ticks are briefly coalesced, then remain usable.
local before = #cor.inputs
assert(cor:action('food') == true)
assert(#cor.inputs == before)
cor:advance(1)
assert(cor:action('food') == true)
assert(#cor.inputs == before + 1)
assert(cor.inputs[#cor.inputs] == '/item "Grape Daifuku" <me>')

-- Fixed actions use exact subjects through the normal input path.
local pld = new_world('PLD')
for _, case in ipairs{
    {'food', nil, '/item "Grape Daifuku" <me>'},
    {'cocoon', nil, '/ma "Cocoon" <me>'},
    {'crusade', nil, '/ma "Crusade" <me>'},
    {'reprisal', nil, '/ma "Reprisal" <me>'},
    {'sentinel-add', nil, '/ja "Sentinel" <me>'},
    {'palisade-add', nil, '/ja "Palisade" <me>'},
    {'blank-gaze-add', pld.astrologer,
        '/ma "Blank Gaze" 17990002'},
    {'flash-add', pld.tormentor, '/ma "Flash" 17990003'},
    {'sheep-song-add', pld.tormentor,
        '/ma "Sheep Song" 17990003'},
    {'geist-wall-add', pld.tormentor,
        '/ma "Geist Wall" 17990003'},
    {'jettatura-add', pld.tormentor,
        '/ma "Jettatura" 17990003'},
} do
    assert(pld:action(case[1], case[2]) == true)
    assert(pld.inputs[#pld.inputs] == case[3])
    pld:advance(1)
end

local dnc = new_world('DNC', {buffs={381}})
assert(dnc:action('lead', dnc.boss) == false)
assert(dnc:action('box-step-add', dnc.tormentor) == true)
assert(dnc.inputs[1] == '/ja "Box Step" 17990003')
dnc:advance(1)
assert(dnc:action('stun-add', dnc.tormentor) == true)
assert(dnc.inputs[2] == '/ja "Violent Flourish" 17990003')

-- Routine pickup builds stock with Box Step. Reactive Violent Flourish is a
-- local no-op without a finishing move or while either ability is on recast,
-- so the controller cannot generate the observed failure-message loop.
local dry_dnc = new_world('DNC')
assert(dry_dnc:action('box-step-add', dry_dnc.tormentor) == true)
assert(dry_dnc.inputs[1] == '/ja "Box Step" 17990003')
dry_dnc:advance(1)
assert(dry_dnc:action('stun-add', dry_dnc.tormentor) == true)
assert(#dry_dnc.inputs == 1)
assert(dry_dnc.adapter.filter_pretarget(manual, nil, {}) == false)
assert(dry_dnc.adapter.filter_precast(manual, nil, {}) == false)
local no_tp_dnc = new_world('DNC', {tp=99})
assert(no_tp_dnc:action('box-step-add', no_tp_dnc.tormentor) == true)
assert(#no_tp_dnc.inputs == 0)
local recast_dnc = new_world('DNC', {
    buffs={381}, ability_recasts={[220]=3,[221]=3},
})
assert(recast_dnc:action('box-step-add', recast_dnc.tormentor) == true)
assert(recast_dnc:action('stun-add', recast_dnc.tormentor) == true)
assert(#recast_dnc.inputs == 0)

-- If the server still rejects a Flourish because its buff snapshot raced,
-- the result itself opens an immediate bounded backoff. Manual callbacks stay
-- unfiltered throughout, and a later valid automatic reaction remains usable.
local failed_dnc = new_world('DNC', {buffs={381}})
assert(failed_dnc:action('stun-add', failed_dnc.tormentor) == true)
assert(#failed_dnc.inputs == 1)
failed_dnc.adapter.action_event({
    category=6, param=207, actor_id=failed_dnc.player.id,
    targets={{id=failed_dnc.tormentor.id, actions={{message=524}}}},
})
failed_dnc:advance(1)
assert(failed_dnc:action('stun-add', failed_dnc.tormentor) == true)
assert(#failed_dnc.inputs == 1,
    'no-finishing-move result did not stop the automatic retry')
assert(failed_dnc.adapter.filter_pretarget(manual, nil, {}) == false)
failed_dnc:advance(10)
assert(failed_dnc:action('stun-add', failed_dnc.tormentor) == true)
assert(#failed_dnc.inputs == 2,
    'bounded failure backoff permanently disabled a valid reaction')

local brd = new_world('BRD')
assert(brd:action('middle', brd.tormentor) == false)
assert(brd:action('clarion') == true)
assert(brd.inputs[1] == '/ja "Clarion Call" <me>')
brd:advance(1)
assert(brd:action('fourth-song') == true)
assert(brd.inputs[2] == '/ma "Knight\'s Minne V" <me>')

local rdm = new_world('RDM')
assert(rdm:action('silence-add', rdm.astrologer) == true)
assert(rdm.inputs[1] == '/ma "Silence" 17990002')
rdm:advance(1)
assert(rdm:action('diaga', rdm.boss) == true)
assert(rdm.inputs[2] == '/ma "Diaga" 17990001')
rdm:advance(1)
assert(rdm:action('cure-iv', 1002) == true)
assert(rdm.inputs[3] == '/ma "Cure IV" 1002')
rdm:advance(1)
assert(rdm:action('wake-pack', 1002) == true)
assert(rdm.inputs[4] == '/ma "Curaga II" 1002')
rdm:advance(1)
assert(rdm:action('dia-iii', rdm.astrologer) == true)
assert(rdm.inputs[5] == '/ma "Dia III" 17990002')

local geo = new_world('GEO')
assert(geo:action('setup', geo.boss) == true)
assert(geo.inputs[1] == '/ma "Geo-Frailty" 17990001')
geo:advance(1)
assert(geo:action('entrust') == true)
assert(geo.inputs[2] == '/ja "Entrust" <me>')
geo:advance(1)
assert(geo:action('indi-wilt', 1002) == true)
assert(geo.inputs[3] == '/ma "Indi-Wilt" 1002')
geo:advance(1)
assert(geo:action('frailty-target', geo.astrologer) == true)
assert(geo.inputs[4] == '/ma "Geo-Frailty" 17990002')
geo:advance(1)
assert(geo:action('flash-add', geo.astrologer) == true)
assert(geo.inputs[5] == '/ma "Flash" 17990002')

-- Runtime-owned healing is subject- and resource-aware. A stale healthy
-- target is a local no-op. The adapter chooses the smallest reviewed ready
-- Cure tier at the exact dispatch edge without an artificial MPP reserve;
-- this never filters a manually entered spell.
local guarded_cures = new_world('RDM')
assert(guarded_cures:action('support-cure', 1002) == true)
assert(#guarded_cures.inputs == 0)
guarded_cures:set_hpp('Tackleberry', 50)
guarded_cures:advance(1)
assert(guarded_cures:action('support-cure', 1002) == true)
assert(guarded_cures.inputs[1] == '/ma "Cure III" 1002')
guarded_cures:aftercast(3, 'Cure III')
guarded_cures:set_hpp('Tackleberry', 100)
guarded_cures:advance(3.1)
guarded_cures:set_mpp(10)
guarded_cures:set_hpp('Kickpuncher', 50)
assert(guarded_cures:action('support-cure', 1003) == true)
assert(guarded_cures.inputs[2] == '/ma "Cure III" 1003',
    'an arbitrary MPP reserve suppressed an affordable exact cure')
guarded_cures:aftercast(3, 'Cure III')
guarded_cures:set_hpp('Kickpuncher', 100)
guarded_cures:advance(3.1)
guarded_cures:set_hpp('Kickpuncher', 24)
assert(guarded_cures:action('support-cure', 1003) == true)
assert(guarded_cures.inputs[3] == '/ma "Cure IV" 1003')
guarded_cures:aftercast(4, 'Cure IV')
guarded_cures:set_hpp('Kickpuncher', 100)
guarded_cures:set_hpp('Barneystinson', 25)
guarded_cures:advance(3.1)
assert(guarded_cures:action('lowhp-cure', 1004) == true)
assert(#guarded_cures.inputs == 3)
guarded_cures:set_hpp('Barneystinson', 12)
guarded_cures:advance(1)
assert(guarded_cures:action('lowhp-cure', 1004) == true)
assert(guarded_cures.inputs[4] == '/ma "Cure II" 1004')

-- The pinned adapter preserves the same exact cure lane before arm/bind and
-- after encounter finish. It selects the lowest in-range living member, and
-- a duplicate controller request cannot create a second cast.
local cure_only = {[1]=true,[2]=true,[3]=true,[4]=true}
local yellow_boundary = new_world('RDM', {
    player_name='Smalls', learned_spells=cure_only,
    usable_spells=cure_only,
})
yellow_boundary:set_hpp('Dolomedes', 75)
assert(yellow_boundary.adapter.pre_tick() == false)
assert(#yellow_boundary.inputs == 0,
    'the exact 75-percent boundary incorrectly entered the cure lane')

local local_cure = new_world('RDM', {player_name='Smalls'})
local_cure:set_hpp('Dolomedes', 74)
local_cure:set_hpp('Barneystinson', 50)
assert(local_cure.adapter.pre_tick() == true)
assert(local_cure.inputs[1] == '/ma "Cure III" 1004',
    'pre-bind support did not select the exact lowest living member')
assert(local_cure:action('support-cure', 1004) == true)
assert(#local_cure.inputs == 1,
    'runtime and local cure entry paths duplicated one pending cast')
local_cure:aftercast(3, 'Cure III')
local_cure:set_hpp('Barneystinson', 100)
local_cure:advance(3.1)
assert(local_cure.adapter.pre_tick() == true)
assert(local_cure.inputs[2] == '/ma "Cure III" 1001',
    'the local cure lane did not continue with the next lowest member')

local convert_yield = new_world('RDM', {
    player_name='Smalls', mpp=29, mp=0,
})
convert_yield:set_hpp('Dolomedes', 50)
assert(convert_yield.adapter.pre_tick() == false,
    'an unavailable Cure below 30 MPP prevented sortieacuex Convert')
convert_yield.player.mpp = 31
assert(convert_yield.adapter.pre_tick() == true,
    'an unavailable Cure above the Convert threshold leaked shared upkeep')

local range_cure = new_world('RDM', {player_name='Smalls'})
range_cure:set_hpp('Dolomedes', 10)
range_cure:set_hpp('Tackleberry', 40)
range_cure.mobs[1001].distance = 500
assert(range_cure.adapter.pre_tick() == true)
assert(range_cure.inputs[1] == '/ma "Cure III" 1002',
    'a known out-of-range member starved an available exact cure target')

-- Profile-local support has exact lifecycle, character, and zone scope.
-- Once this adapter is replaced/deactivated it cannot leak a Cure or opening
-- spell into another profile, and an unrelated RDM never owns this lane.
local stopped_support = new_world('RDM', {player_name='Smalls'})
stopped_support:set_hpp('Dolomedes', 20)
stopped_support.adapter.deactivate()
assert(stopped_support.adapter.pre_tick() == false)
stopped_support.adapter.prerender()
assert(#stopped_support.inputs == 0,
    'deactivated no-Cait support leaked into another profile')
local wrong_zone_support = new_world('RDM', {
    player_name='Smalls', zone=130,
})
wrong_zone_support:set_hpp('Dolomedes', 20)
assert(wrong_zone_support.adapter.pre_tick() == false)
wrong_zone_support.adapter.prerender()
assert(#wrong_zone_support.inputs == 0,
    'no-Cait support leaked outside its exact Ambuscade zones')
local wrong_actor_support = new_world('RDM', {player_name='Dolomedes'})
wrong_actor_support:set_hpp('Tackleberry', 20)
assert(wrong_actor_support.adapter.pre_tick() == false)
wrong_actor_support.adapter.prerender()
assert(#wrong_actor_support.inputs == 0,
    'no-Cait support leaked onto an RDM other than Smalls')

-- Opening defense is adapter-local: one learned Shellra, then five living
-- non-RDM Protect targets. The immutable sortieacuex helper resumes only
-- after this bounded overlay is complete. A known dead defense member is
-- skipped instead of trapping the scheduler on a failed cast.
local opening = new_world('RDM', {player_name='Smalls'})
opening:set_hpp('Achoo', 0)
assert(opening.adapter.pre_tick() == true)
assert(opening.inputs[1] == '/ma "Shellra V" <me>')
opening:aftercast(134, 'Shellra V')
opening:advance(3.1)
for index, target_id in ipairs{1004,1001,1003,1002} do
    assert(opening.adapter.pre_tick() == true)
    assert(opening.inputs[index + 1]
        == '/ma "Protect V" '..tostring(target_id))
    opening:aftercast(47, 'Protect V')
    opening:advance(3.1)
end
assert(opening.adapter.pre_tick() == false,
    'completed opening defense did not yield to sortieacuex upkeep')
opening:set_mpp(31)
assert(opening.adapter.pre_tick() == true,
    'ordinary shared upkeep was not held inside the 30-34 MPP band')

-- If /WHM has no learned Shellra, the same bounded opening falls back to
-- individual Shell on living defense targets without touching shared state.
local no_shellra = {}
for id=1,52 do no_shellra[id] = true end
local shell_fallback = new_world('RDM', {
    player_name='Smalls', learned_spells=no_shellra,
    usable_spells=no_shellra,
})
assert(shell_fallback.adapter.pre_tick() == true)
assert(shell_fallback.inputs[1] == '/ma "Shell V" 1006')

-- The 35% opening floor is evaluated after Protect's MP cost. A blocked
-- automatic cast still consumes only the helper tick; manual callbacks stay
-- unfiltered and the cast becomes eligible as soon as the reserve is met.
local floor = new_world('RDM', {
    player_name='Smalls', mp=433, max_mp=1000, mpp=43.3,
})
assert(floor.adapter.pre_tick() == true)
assert(floor.inputs[1] == '/ma "Shellra V" <me>')
floor:aftercast(134, 'Shellra V')
floor:advance(3.1)
assert(floor.adapter.pre_tick() == true)
assert(#floor.inputs == 1,
    'Protect crossed the reviewed 35-percent post-cast opening floor')
floor.player.mp, floor.player.mpp = 434, 43.4
assert(floor.adapter.pre_tick() == true)
assert(floor.inputs[2] == '/ma "Protect V" 1006')

-- A completed Convert gives self recovery the next automatic action. Runtime
-- cure requests defer during that bounded window, but all manual hooks remain
-- unconditional pass-through.
local recovery = new_world('RDM', {player_name='Smalls', hpp=20})
recovery:aftercast(nil, 'Convert')
recovery:set_hpp('Dolomedes', 10)
assert(recovery:action('support-cure', 1001) == true)
assert(#recovery.inputs == 0)
assert(recovery.adapter.pre_tick() == true)
assert(recovery.inputs[1] == '/ma "Cure IV" <me>')
assert(recovery.adapter.filter_pretarget(manual, nil, {}) == false)
assert(recovery.adapter.filter_precast(manual, nil, {}) == false)

-- Tackle's backup is emergency-only and revalidates the exact member at the
-- adapter edge, independently of Smalls' request.
local tackle_cure = new_world('PLD', {player_name='Tackleberry'})
tackle_cure:set_hpp('Barneystinson', 40)
assert(tackle_cure:action('emergency-cure', 1004) == true)
assert(tackle_cure.inputs[1] == '/ma "Cure IV" 1004')
tackle_cure:set_hpp('Barneystinson', 41)
tackle_cure:advance(1)
assert(tackle_cure:action('emergency-cure', 1004) == true)
assert(#tackle_cure.inputs == 1,
    'Tackle emergency cure fired above its exact 40-percent threshold')

local far_tackle_cure = new_world('PLD', {player_name='Tackleberry'})
far_tackle_cure:set_hpp('Barneystinson', 40)
far_tackle_cure.mobs[1004].distance = 500
assert(far_tackle_cure:action('emergency-cure', 1004) == true)
assert(#far_tackle_cure.inputs == 0,
    'Tackle emergency cure fired at a known out-of-range member')

local missing_tackle_cure = new_world('PLD', {player_name='Tackleberry'})
missing_tackle_cure:set_hpp('Barneystinson', 40)
missing_tackle_cure.mobs[1004] = nil
assert(missing_tackle_cure:action('emergency-cure', 1004) == true)
assert(#missing_tackle_cure.inputs == 0,
    'Tackle emergency cure fired without target geometry')

local invalid_tackle_cure = new_world('PLD', {player_name='Tackleberry'})
invalid_tackle_cure:set_hpp('Barneystinson', 40)
invalid_tackle_cure.mobs[1004].distance = -1
assert(invalid_tackle_cure:action('emergency-cure', 1004) == true)
assert(#invalid_tackle_cure.inputs == 0,
    'Tackle emergency cure accepted a negative distance sentinel')

-- Shadows are locally count-aware and loss-reactive. Ni tops one/two copies,
-- holds at three or more, and Ichi is reserved for zero. The slow runtime
-- request is only a recovery watchdog for a missed transition or failed cast.
for _, buff in ipairs{445,446} do
    local full = new_world('COR', {buffs={buff}})
    assert(full:action('shadow-ni') == true)
    assert(#full.inputs == 0)
end
for _, buff in ipairs{66,444} do
    local partial = new_world('COR', {buffs={buff}})
    assert(partial:action('shadow-ni') == true)
    assert(partial.inputs[1] == '/ma "Utsusemi: Ni" <me>')
end
local unshadowed = new_world('COR')
assert(unshadowed:action('shadow-ni') == true)
assert(unshadowed.inputs[1] == '/ma "Utsusemi: Ni" <me>')
local ichi_held = new_world('BRD', {buffs={66}})
assert(ichi_held:action('shadow-ichi') == true)
assert(#ichi_held.inputs == 0)
local ichi_needed = new_world('BRD')
assert(ichi_needed:action('shadow-ichi') == true)
assert(ichi_needed.inputs[1] == '/ma "Utsusemi: Ichi" <me>')

local reactive = new_world('DNC', {buffs={445}})
assert(reactive:action('shadow-ni') == true)
assert(#reactive.inputs == 0)
reactive.player.buffs = {444}
reactive:advance(.2)
reactive.adapter.prerender()
assert(reactive.inputs[1] == '/ma "Utsusemi: Ni" <me>',
    'loss of a local Copy Image did not trigger immediate Ni')
reactive.player.buffs = {445}
reactive:advance(.2)
reactive.adapter.prerender()
assert(#reactive.inputs == 1, 'gaining shadows submitted another cast')
assert(reactive:action('cancel') == true)
reactive.player.buffs = {444}
reactive:advance(.2)
reactive.adapter.prerender()
assert(#reactive.inputs == 1, 'cancel left the local shadow watch running')

-- At zero copies, live recasts select Ichi immediately when Ni is not ready.
-- Partial stacks are never cancelled just to force Ichi over Ni.
local zero_fallback_recasts = {[338]=0,[339]=100}
local zero_fallback = new_world('DNC', {
    spell_recasts=zero_fallback_recasts,
})
assert(zero_fallback:action('shadow-ni') == true)
assert(zero_fallback.inputs[1] == '/ma "Utsusemi: Ichi" <me>')
local partial_no_ichi = new_world('DNC', {
    buffs={444}, spell_recasts={[338]=0,[339]=100},
})
assert(partial_no_ichi:action('shadow-ni') == true)
assert(#partial_no_ichi.inputs == 0)

-- If both tiers are initially unavailable, the local watcher retries and
-- starts Ichi as soon as its recast opens; it does not wait ten seconds.
local exhausted_recasts = {[338]=100,[339]=100}
local exhausted = new_world('BRD', {spell_recasts=exhausted_recasts})
assert(exhausted:action('shadow-ni') == true)
assert(#exhausted.inputs == 0)
exhausted_recasts[338] = 0
exhausted:advance(.8)
exhausted.adapter.prerender()
assert(exhausted.inputs[1] == '/ma "Utsusemi: Ichi" <me>')

local reraise_magic = new_world('RDM')
assert(reraise_magic:action('reraise') == true)
assert(reraise_magic.inputs[1] == '/ma "Reraise" <me>')
local reraise_present = new_world('GEO', {buffs={113}})
assert(reraise_present:action('reraise') == true)
assert(#reraise_present.inputs == 0)
local reraise_item = new_world('PLD', {
    items={{id=4172,count=1},{id=6697,count=1}},
})
assert(reraise_item:action('reraise') == true)
assert(reraise_item.inputs[1] == '/item "Instant Reraise III" <me>')
local no_reraise_item = new_world('BRD')
assert(no_reraise_item:action('reraise') == false)
assert(#no_reraise_item.inputs == 0)

-- Legacy capture/low-HP control messages are harmless compatibility no-ops.
assert(pld:action('capture-on') == true)
assert(rdm:action('lowhp-on') == true)
assert(#pld.inputs == 11 and #rdm.inputs == 5)

-- Exact identity validation rejects unrelated, foreign, or distant entities.
local exact = new_world('RDM')
exact.astrologer.claim_id = 9999
assert(exact:action('silence-add', exact.astrologer) == false)
exact.astrologer.claim_id = 0
exact.astrologer.x = 100
assert(exact:action('silence-add', exact.astrologer) == false)
exact.astrologer.x = 30
assert(exact:action('silence-add', exact.astrologer) == true)
exact.boss.name = 'Not Bigwig'
exact:advance(1)
assert(exact:action('diaga', exact.boss) == false)
local wrong_zone = new_world('COR', {zone=130})
assert(wrong_zone:action('pull', wrong_zone.boss) == false)

-- Windower resource projections may compact and truncate long entity names.
local compact = new_world('PLD')
compact.boss.name = 'BozzettoBigwig'
compact.astrologer.name = 'BozzettoAstrol'
compact.tormentor.name = 'BozzettoTormen'
assert(compact:action('blank-gaze-add', compact.astrologer) == true)
compact:advance(1)
assert(compact:action('flash-add', compact.tormentor) == true)

-- Area tags revalidate geometry at dispatch time. Exact Flash/Gaze and every
-- other combat lane remain available when Bigwig has followed the kill group.
local unsafe = new_world('PLD')
unsafe.tormentor.x = 3
unsafe.mobs[unsafe.player.id].x = 3
assert(unsafe:action('flash-add', unsafe.tormentor) == true)
unsafe:advance(1)
assert(unsafe:action('blank-gaze-add', unsafe.tormentor) == true)
unsafe:advance(1)
assert(unsafe:action('jettatura-add', unsafe.tormentor) == false)
unsafe:advance(1)
assert(unsafe:action('geist-wall-add', unsafe.tormentor) == false)
unsafe:advance(1)
assert(unsafe:action('sheep-song-add', unsafe.tormentor) == false)

-- Fifteen yalms is sufficient once Tackle has actually reached 4.5 yalms;
-- neither a longer cross-room split nor a 20-yalm threshold is required.
local compact_safe = new_world('PLD')
compact_safe.tormentor.x = 15
compact_safe.mobs[compact_safe.player.id].x = 10.5
assert(compact_safe:action('geist-wall-add', compact_safe.tormentor) == true)
local compact_not_arrived = new_world('PLD')
compact_not_arrived.tormentor.x = 15
compact_not_arrived.mobs[compact_not_arrived.player.id].x = 10.49
assert(compact_not_arrived:action(
    'geist-wall-add', compact_not_arrived.tormentor) == false)

-- Probe output is diagnostics only, and teardown reports its loss.
local probe = cor.adapter.handle_action('qutrub-bigwig-no-cait', 'probe', {
    '1700000000-1001-1', '0', '1',
})
assert(probe == true)
assert(cor.commands[#cor.commands]
    == 'pt __controller_ready qutrub-bigwig-no-cait '
        ..'1700000000-1001-1 0 1')
local status = cor.adapter.status()
assert(type(status) == 'string')
assert(status:find('manual-pass-through', 1, true))
assert(cor.adapter.deactivate('test') == true)
assert(cor.commands[#cor.commands]
    == 'pt __controller_lost qutrub-bigwig-no-cait '
        ..'1700000000-1001-1 0 1')

print('September Qutrub no-Cait cooperative adapter tests passed.')
