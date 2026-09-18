-- PartyTactics GearSwap adapter: bounded exact-entity reservations for the
-- September Qutrub/Bozzetto Bigwig profile. The stable host owns callbacks;
-- the character's normal GearSwap file remains the sole equipment owner.

local M = {
    id = 'ambuscade-2026-09-v1-qutrub-bigwig',
    version = '1.0.0',
    controller = 'qutrub-bigwig',
    protocol = 1,
}

local BOSS = 'Bozzetto Bigwig'
local ASTROLOGER = 'Bozzetto Astrologer'
local TORMENTORS = {
    ['Bozzetto Tormentor']=true,
    ['Bozzetto Tormenter']=true,
}
local AMBUSCADE_ZONES = {[183]=true, [287]=true}
local EXPECTED_SUBJOBS = {
    COR='NIN', PLD='NIN', DNC='NIN', BRD='SMN', RDM='WHM', GEO='SMN',
}

local POLL_INTERVAL = 0.10
local RETRY_DELAY = 0.40
local RESULT_TIMEOUT = 7.0
local DISPATCH_TOKEN = 1.0
local TICK_DELAY = 1.5
local EMERGENCY_HPP = 60
local MAX_MODEL_SIZE = 10
local FOOD_ID = 6343
local FOOD_BUFF_ID = 251
local INDI_FURY_BUFF_ID = 549
local CLARION_BUFF_ID = 499
local MAJESTY_BUFF_ID = 621
local COPY_IMAGE_BUFFS = {[66]=1, [444]=2, [445]=3, [446]=4}
local LOWHP_CONTROL_TTL = 6.0
local LOWHP_ATTACKER_MIN = 13
local LOWHP_ATTACKER_MAX = 25
local LOWHP_SUPPORT_MIN = 60
local LOWHP_CURE_RADIUS = 20

local ATTACKER_NAMES = {
    Dolomedes=true, Tackleberry=true, Kickpuncher=true,
}
local SUPPORT_NAMES = {
    Barneystinson=true, Smalls=true, Achoo=true,
}

local ALL_SUBJECTS = {
    [BOSS]=true,
    [ASTROLOGER]=true,
    ['Bozzetto Tormentor']=true,
    ['Bozzetto Tormenter']=true,
}
local BOSS_ONLY = {[BOSS]=true}
local ASTRO_ONLY = {[ASTROLOGER]=true}
local ADD_ONLY = {
    [ASTROLOGER]=true,
    ['Bozzetto Tormentor']=true,
    ['Bozzetto Tormenter']=true,
}

local ACTIONS = {
    COR = {
        food={kind='item', id=FOOD_ID, name='Grape Daifuku', category=5,
            command='/item', target='self', ttl=12, max_attempts=2,
            priority=100, allow_unclaimed=true, status='food'},
        ['shadow-ni']={kind='spell', id=339, name='Utsusemi: Ni', category=4,
            command='/ma', target='self', ttl=10, max_attempts=3,
            priority=95, allow_unclaimed=true, shadow_min=2,
            opportunistic=true},
        ['shadow-ichi']={kind='spell', id=338, name='Utsusemi: Ichi',
            category=4, command='/ma', target='self', ttl=12,
            max_attempts=3, priority=94, allow_unclaimed=true, shadow_min=1},
        close={kind='weaponskill', id=221, name='Last Stand', category=3,
            command='/ws', target='enemy', range=19.7, min_tp=1000,
            ttl=8, max_attempts=3, priority=50, subjects=ALL_SUBJECTS,
            offense=true, requires_food=true, requires_shadow=true},
    },
    DNC = {
        food={kind='item', id=FOOD_ID, name='Grape Daifuku', category=5,
            command='/item', target='self', ttl=12, max_attempts=2,
            priority=100, allow_unclaimed=true, status='food'},
        ['shadow-ni']={kind='spell', id=339, name='Utsusemi: Ni', category=4,
            command='/ma', target='self', ttl=10, max_attempts=3,
            priority=95, allow_unclaimed=true, shadow_min=2,
            opportunistic=true},
        ['shadow-ichi']={kind='spell', id=338, name='Utsusemi: Ichi',
            category=4, command='/ma', target='self', ttl=12,
            max_attempts=3, priority=94, allow_unclaimed=true, shadow_min=1},
        lead={kind='weaponskill', id=25, name='Evisceration', category=3,
            command='/ws', target='enemy', range=3.2, min_tp=1000,
            ttl=8, max_attempts=3, priority=50, subjects=ALL_SUBJECTS,
            offense=true, requires_food=true, requires_shadow=true},
    },
    PLD = {
        food={kind='item', id=FOOD_ID, name='Grape Daifuku', category=5,
            command='/item', target='self', ttl=12, max_attempts=2,
            priority=100, allow_unclaimed=true, status='food'},
        ['shadow-ni']={kind='spell', id=339, name='Utsusemi: Ni', category=4,
            command='/ma', target='self', ttl=10, max_attempts=3,
            priority=95, allow_unclaimed=true, shadow_min=2,
            opportunistic=true},
        ['shadow-ichi']={kind='spell', id=338, name='Utsusemi: Ichi',
            category=4, command='/ma', target='self', ttl=12,
            max_attempts=3, priority=94, allow_unclaimed=true, shadow_min=1},
        crusade={kind='spell', id=476, name='Crusade', category=4,
            command='/ma', target='self', ttl=12, max_attempts=3,
            priority=90, allow_unclaimed=true, opportunistic=true},
        ['divine-emblem']={kind='job_ability', id=255,
            name='Divine Emblem', category=6, command='/ja', target='self',
            ttl=5, max_attempts=1, priority=90, allow_unclaimed=true,
            opportunistic=true},
        sentinel={kind='job_ability', id=48, name='Sentinel', category=6,
            command='/ja', target='self', ttl=10, max_attempts=3,
            priority=90, allow_unclaimed=true, opportunistic=true},
        rampart={kind='job_ability', id=92, name='Rampart', category=6,
            command='/ja', target='self', ttl=10, max_attempts=3,
            priority=90, allow_unclaimed=true, opportunistic=true},
        palisade={kind='job_ability', id=278, name='Palisade', category=6,
            command='/ja', target='self', ttl=10, max_attempts=3,
            priority=90, allow_unclaimed=true, opportunistic=true},
        flash={kind='spell', id=112, name='Flash', category=4,
            command='/ma', target='enemy', range=12, ttl=12,
            max_attempts=3, priority=90, allow_unclaimed=true,
            subjects=BOSS_ONLY, requires_food=true},
        ['flash-add']={kind='spell', id=112, name='Flash', category=4,
            command='/ma', target='enemy', range=12, ttl=12,
            max_attempts=3, priority=92, subjects=ADD_ONLY,
            requires_food=true, opportunistic=true},
        middle={kind='weaponskill', id=42, name='Savage Blade', category=3,
            command='/ws', target='enemy', range=3.2, min_tp=1000,
            ttl=8, max_attempts=3, priority=50, subjects=ALL_SUBJECTS,
            offense=true, requires_food=true, requires_shadow=true},
    },
    BRD = {
        summon={kind='spell', id=307, name='Cait Sith', category=4,
            command='/ma', target='self', ttl=12, max_attempts=3,
            priority=80, allow_unclaimed=true, status='cait-sith'},
        mew={kind='pet_ability', id=522, result_ids={[522]=true,[2449]=true},
            result_categories={[6]=true,[11]=true}, name='Mewing Lullaby',
            category=11, command='/pet', target='enemy', range=14,
            ttl=12, max_attempts=3, priority=85, subjects=BOSS_ONLY,
            requires_pet=true},
        clarion={kind='job_ability', id=332, name='Clarion Call', category=6,
            command='/ja', target='self', ttl=5, max_attempts=1,
            priority=30, allow_unclaimed=true, opportunistic=true},
        ['fourth-song']={kind='spell', id=393, name="Knight's Minne V",
            category=4, command='/ma', target='self', ttl=10,
            max_attempts=2, priority=30, allow_unclaimed=true,
            requires_clarion=true, opportunistic=true},
    },
    RDM = {
        ['lowhp-cure']={kind='spell', id=2, name='Cure II', category=4,
            command='/ma', target='party', range=20.4, ttl=8,
            max_attempts=2, priority=100, party_subjects=ATTACKER_NAMES,
            recovery=true, requires_lowhp_guard=true},
        ['support-cure']={kind='spell', id=4, name='Cure IV', category=4,
            command='/ma', target='party', range=20.4, ttl=8,
            max_attempts=2, priority=99, party_subjects=SUPPORT_NAMES,
            recovery=true, requires_lowhp_guard=true},
        ['silence-add']={kind='spell', id=59, name='Silence', category=4,
            command='/ma', target='enemy', range=12, ttl=12,
            max_attempts=3, priority=85, subjects=ASTRO_ONLY,
            opportunistic=true},
        ['dispel-ice-spikes']={kind='spell', id=260, name='Dispel',
            category=4, command='/ma', target='enemy', range=12, ttl=10,
            max_attempts=3, priority=96, subjects=ASTRO_ONLY,
            opportunistic=true},
        diaga={kind='spell', id=33, name='Diaga', category=4,
            command='/ma', target='enemy', range=12, ttl=10,
            max_attempts=3, priority=90, subjects=BOSS_ONLY},
        ['silence-boss']={kind='spell', id=59, name='Silence', category=4,
            command='/ma', target='enemy', range=12, ttl=12,
            max_attempts=3, priority=70, subjects=BOSS_ONLY},
    },
    GEO = {
        summon={kind='spell', id=307, name='Cait Sith', category=4,
            command='/ma', target='self', ttl=12, max_attempts=3,
            priority=80, allow_unclaimed=true, status='cait-sith'},
        mew={kind='pet_ability', id=522, result_ids={[522]=true,[2449]=true},
            result_categories={[6]=true,[11]=true}, name='Mewing Lullaby',
            category=11, command='/pet', target='enemy', range=14,
            ttl=12, max_attempts=3, priority=85, subjects=BOSS_ONLY,
            requires_pet=true},
        setup={kind='spell', id=818, name='Geo-Frailty', category=4,
            command='/ma', target='enemy', range=20.4, ttl=12,
            max_attempts=3, priority=80, subjects=BOSS_ONLY,
            requires_indi_fury=true},
    },
}

local FAILURE_MESSAGES = {
    [4]=true, [5]=true, [16]=true, [17]=true, [18]=true, [29]=true,
    [34]=true, [40]=true, [47]=true, [48]=true, [49]=true,
    [71]=true, [72]=true, [75]=true, [76]=true, [78]=true,
    [84]=true, [85]=true, [86]=true, [87]=true, [88]=true,
    [89]=true, [90]=true, [94]=true, [106]=true, [114]=true,
    [128]=true, [154]=true, [155]=true, [156]=true, [158]=true,
    [188]=true, [189]=true, [190]=true, [191]=true, [192]=true,
    [193]=true, [198]=true, [217]=true, [219]=true, [248]=true,
    [283]=true, [284]=true, [313]=true, [316]=true, [323]=true,
    [325]=true, [328]=true, [355]=true, [422]=true, [423]=true,
    [649]=true, [655]=true, [656]=true, [659]=true, [661]=true,
}

local queue = {
    request=nil, last_result='idle', accepted=0, dispatched=0,
    completed=0, rejected=0, next_poll=0,
}
local capability = nil
local binding = nil
local lowhp_guard = nil

if rawget(_G, 'PARTYTACTICS_QUTRUB_TEST_MODE') == true then
    M._test_queue = queue
    M._test_binding = function() return binding end
end

local function chat(color, message)
    if type(add_to_chat) == 'function' then
        add_to_chat(color, '[PartyTactics Qutrub] '..message)
    end
end

local function uint32(value)
    if type(value) ~= 'string' or #value == 0 or #value > 10
        or value:match('^%d+$') == nil
    then
        return nil
    end
    local number = tonumber(value)
    if not number or number < 1 or number > 4294967295
        or number ~= math.floor(number)
    then
        return nil
    end
    return number
end

local function nonnegative_integer(value)
    if type(value) ~= 'string' or #value == 0 or #value > 12
        or value:match('^%d+$') == nil
    then
        return nil
    end
    local number = tonumber(value)
    return number and number >= 0 and number == math.floor(number)
        and number or nil
end

local function local_player()
    local live = windower.ffxi.get_player()
    return player or live, live
end

local function local_job()
    local current, live = local_player()
    return current and current.main_job or live and live.main_job or nil
end

local function local_subjob()
    local current, live = local_player()
    return current and current.sub_job or live and live.sub_job or nil
end

local function dead()
    local current, live = local_player()
    local hpp = current and tonumber(current.hpp) or nil
    if hpp == nil and live and live.vitals then hpp = live.vitals.hpp end
    local status = current and current.status or live and live.status or nil
    return (tonumber(hpp) or 100) <= 0 or status == 2
        or type(status) == 'string'
            and status:lower():find('dead', 1, true) ~= nil
end

local function probe(generation, epoch_value, protocol_value)
    local epoch = nonnegative_integer(epoch_value)
    local protocol = nonnegative_integer(protocol_value)
    local job, subjob = local_job(), local_subjob()
    if type(generation) ~= 'string' or #generation > 64
        or generation:match('^%d+%-%d+%-%d+$') == nil
        or epoch == nil or protocol ~= M.protocol
        or not ACTIONS[job] or subjob ~= EXPECTED_SUBJOBS[job]
    then
        return false, 'invalid job, subjob, or controller probe'
    end
    if capability and (capability.generation ~= generation
        or capability.epoch ~= epoch)
    then
        queue.request = nil
        binding = nil
        lowhp_guard = nil
    end
    capability = {
        generation=generation, epoch=epoch, protocol=protocol,
        job=job, subjob=subjob,
    }
    windower.send_command(
        ('pt __controller_ready qutrub-bigwig %s %d %d')
            :format(generation, epoch, protocol))
    return true, 'ready'
end

local function report_lost()
    local old = capability
    capability = nil
    binding = nil
    lowhp_guard = nil
    queue.request = nil
    if old then
        windower.send_command(
            ('pt __controller_lost qutrub-bigwig %s %d %d')
                :format(old.generation, old.epoch, old.protocol))
    end
end

local function authorized(generation, epoch_value)
    local epoch = nonnegative_integer(epoch_value)
    return type(generation) == 'string'
        and generation:match('^%d+%-%d+%-%d+$') ~= nil
        and epoch ~= nil and capability ~= nil
        and capability.generation == generation
        and capability.epoch == epoch
        and capability.protocol == M.protocol
        and capability.job == local_job()
        and capability.subjob == local_subjob(), epoch
end

local function party_claimed(mob)
    local claim = mob and tonumber(mob.claim_id)
    if not claim or claim == 0 then return false end
    local current = windower.ffxi.get_player()
    if current and tonumber(current.id) == claim then return true end
    for key, member in pairs(windower.ffxi.get_party() or {}) do
        if type(member) == 'table'
            and (type(key) ~= 'string' or key:match('^p[0-5]$'))
        then
            local id = member.mob and tonumber(member.mob.id)
                or tonumber(member.mob_id) or tonumber(member.id)
            if id == claim then return true end
        end
    end
    return false
end

local function exact_entity(mob, name, id, index)
    return type(mob) == 'table' and mob.name == name
        and mob.spawn_type == 16 and mob.id == id and mob.index == index
        and mob.valid_target == true and (tonumber(mob.hpp) or 0) > 0
end

local function exact_boss(mob, request)
    return exact_entity(mob, BOSS,
        request.encounter_id, request.encounter_index)
end

local function party_subject_by_id(wanted_id, allowed, wanted_name,
    wanted_index)
    wanted_id = tonumber(wanted_id)
    if not wanted_id or type(allowed) ~= 'table' then return nil end
    local party = windower.ffxi.get_party() or {}
    for index = 0, 5 do
        local member = party['p'..tostring(index)]
        local member_id = type(member) == 'table' and (
            member.mob and tonumber(member.mob.id)
                or tonumber(member.mob_id) or tonumber(member.id)) or nil
        local name = type(member) == 'table' and member.name or nil
        if member_id == wanted_id and type(name) == 'string'
            and allowed[name] and (not wanted_name or name == wanted_name)
        then
            local live = windower.ffxi.get_mob_by_id(wanted_id)
                or member.mob or {}
            local live_index = tonumber(live.index)
                or tonumber(member.mob and member.mob.index)
            local live_hpp = tonumber(live.hpp)
            local hpp = tonumber(member.hpp) or live_hpp
            if live_index and live_index >= 0 and live_index <= 65535
                and live_index == math.floor(live_index)
                and (not wanted_index
                    or live_index == tonumber(wanted_index))
                and hpp and hpp > 0 and live_hpp and live_hpp > 0
                and live.name == name
                and live.valid_target == true
            then
                return {
                    id=wanted_id, index=live_index, name=name, hpp=hpp,
                    valid_target=true, distance=live.distance,
                    model_size=live.model_size, x=live.x, y=live.y,
                }
            end
        end
    end
    return nil
end

local function party_hpp_by_name(wanted)
    for index = 0, 5 do
        local member = (windower.ffxi.get_party() or {})[
            'p'..tostring(index)]
        if type(member) == 'table' and member.name == wanted then
            return tonumber(member.hpp)
        end
    end
    return nil
end

local function party_subject_by_name(wanted, allowed)
    local party = windower.ffxi.get_party() or {}
    for index = 0, 5 do
        local member = party['p'..tostring(index)]
        if type(member) == 'table' and member.name == wanted then
            local id = member.mob and tonumber(member.mob.id)
                or tonumber(member.mob_id) or tonumber(member.id)
            return id and party_subject_by_id(id, allowed, wanted) or nil
        end
    end
    return nil
end

local function clear_lowhp_recovery(reason, encounter_id)
    local request = queue.request
    local action = request and ACTIONS[request.job]
        and ACTIONS[request.job][request.semantic] or nil
    if request and action and action.requires_lowhp_guard
        and (not encounter_id or request.encounter_id == encounter_id)
    then
        queue.request = nil
        queue.last_result = reason or 'low-HP authority ended'
    end
end

local function lowhp_active()
    local guard = lowhp_guard
    if not guard then return false end
    local info = windower.ffxi.get_info()
    local boss = windower.ffxi.get_mob_by_id(guard.encounter_id)
    if os.clock() >= guard.expires
        or not authorized(guard.generation, tostring(guard.epoch))
        or not info or not info.logged_in or info.zone ~= guard.zone
        or not AMBUSCADE_ZONES[info.zone]
        or not boss or not exact_boss(boss, guard)
        or not party_claimed(boss)
    then
        lowhp_guard = nil
        clear_lowhp_recovery('low-HP authority expired')
        return false
    end
    return true
end

local function matching_lowhp_guard(encounter_id, generation, epoch)
    return lowhp_active() and lowhp_guard.encounter_id == encounter_id
        and lowhp_guard.generation == generation
        and lowhp_guard.epoch == epoch
end

local function squared_separation(left, right)
    if type(left) ~= 'table' or type(right) ~= 'table'
        or type(left.x) ~= 'number' or type(left.y) ~= 'number'
        or type(right.x) ~= 'number' or type(right.y) ~= 'number'
    then
        return nil
    end
    local dx, dy = left.x - right.x, left.y - right.y
    return dx * dx + dy * dy
end

local function associated_subject(boss, subject)
    if subject.id == boss.id and subject.index == boss.index then return true end
    if party_claimed(subject) then return true end
    if (tonumber(subject.claim_id) or 0) ~= 0 then return false end
    local separation = squared_separation(boss, subject)
    if separation then return separation <= 35 * 35 end
    local bd, sd = tonumber(boss.distance), tonumber(subject.distance)
    return bd ~= nil and sd ~= nil and bd >= 0 and sd >= 0
        and bd <= 35 * 35 and sd <= 35 * 35
end

local function has_buff(id)
    local current = windower.ffxi.get_player()
    for _, buff_id in pairs(current and current.buffs or {}) do
        if tonumber(buff_id) == id then return true end
    end
    return false
end

local function copy_images()
    local count = 0
    local current = windower.ffxi.get_player()
    for _, buff_id in pairs(current and current.buffs or {}) do
        count = math.max(count, COPY_IMAGE_BUFFS[tonumber(buff_id)] or 0)
    end
    return count
end

local function cait_sith()
    local candidate = type(pet) == 'table' and pet or nil
    if (not candidate or candidate.isvalid == false)
        and type(windower.ffxi.get_mob_by_target) == 'function'
    then
        candidate = windower.ffxi.get_mob_by_target('pet')
    end
    return type(candidate) == 'table'
        and candidate.name == 'Cait Sith'
        and candidate.isvalid ~= false and candidate.valid_target ~= false
        and candidate or nil
end

local function clear(reason, announce)
    local request = queue.request
    queue.request = nil
    queue.last_result = reason or 'cancelled'
    if request and announce then
        chat(123, ('%s #%d cancelled: %s.'):format(
            request.semantic, request.subject_id, tostring(reason)))
    end
end

local function resource(action)
    if not action or type(res) ~= 'table' then return nil end
    local collection
    if action.kind == 'weaponskill' then
        collection = res.weapon_skills
    elseif action.kind == 'job_ability' or action.kind == 'pet_ability' then
        collection = res.job_abilities
    elseif action.kind == 'spell' then
        collection = res.spells
    elseif action.kind == 'item' then
        collection = res.items
    end
    local value = collection and collection[action.id] or nil
    if not value or value.id ~= action.id
        or (value.en or value.english) ~= action.name
    then
        return nil
    end
    return value
end

local function collection_has(collection, id)
    if type(collection) ~= 'table' then return false end
    if collection[id] == true or collection[id] == 1
        or tonumber(collection[id]) == id
    then
        return true
    end
    for key, value in pairs(collection) do
        if tonumber(value) == id
            or (value == true or value == 1) and tonumber(key) == id
        then
            return true
        end
    end
    return false
end

local function has_item(id)
    local inventory = windower.ffxi.get_items(0) or {}
    for key, item in pairs(inventory) do
        if key ~= 'max' and key ~= 'count' and type(item) == 'table'
            and tonumber(item.id) == id and (tonumber(item.count) or 0) > 0
        then
            return true
        end
    end
    return false
end

local function learned(action)
    if action.kind == 'item' then return has_item(action.id) end
    if action.kind == 'spell' then
        return collection_has(windower.ffxi.get_spells() or {}, action.id)
    end
    local abilities = windower.ffxi.get_abilities() or {}
    local collection = action.kind == 'weaponskill'
        and abilities.weapon_skills or abilities.job_abilities
    return collection_has(collection or {}, action.id)
end

local function function_true(name, ...)
    local callback = _G[name]
    if type(callback) ~= 'function' then return false end
    local ok, value = pcall(callback, ...)
    return ok and value == true
end

local function lowest_party_hpp()
    local floor = 100
    local party_table = windower.ffxi.get_party() or {}
    for index = 0, 5 do
        local member = party_table['p'..tostring(index)]
        if type(member) ~= 'table' or type(member.hpp) ~= 'number' then
            return 0
        end
        floor = math.min(floor, member.hpp)
    end
    return floor
end

local function lowhp_offense_ready()
    if not lowhp_active() then return lowest_party_hpp() >= EMERGENCY_HPP end
    for name in pairs(ATTACKER_NAMES) do
        local hpp = party_hpp_by_name(name)
        if not hpp or hpp < LOWHP_ATTACKER_MIN
            or hpp > LOWHP_ATTACKER_MAX
        then
            return false
        end
    end
    local boss = lowhp_guard
        and windower.ffxi.get_mob_by_id(lowhp_guard.encounter_id) or nil
    for name in pairs(SUPPORT_NAMES) do
        local hpp = party_hpp_by_name(name)
        local mob = party_subject_by_name(name, SUPPORT_NAMES)
        local separation = squared_separation(boss, mob)
        if not hpp or hpp < LOWHP_SUPPORT_MIN or not separation
            or separation <= 16 * 16
        then
            return false
        end
    end
    local smalls = party_subject_by_name('Smalls', SUPPORT_NAMES)
    if not smalls then return false end
    for name in pairs(ATTACKER_NAMES) do
        local attacker = party_subject_by_name(name, ATTACKER_NAMES)
        local separation = squared_separation(smalls, attacker)
        if not separation
            or separation > LOWHP_CURE_RADIUS * LOWHP_CURE_RADIUS
        then
            return false
        end
    end
    return true
end

local function lowhp_support_floor()
    local floor = 100
    for name in pairs(SUPPORT_NAMES) do
        local hpp = party_hpp_by_name(name)
        if not hpp then return 0 end
        floor = math.min(floor, hpp)
    end
    return floor
end

local function recovery_needed()
    local buffs = buffactive or {}
    return buffs.Doom or buffs.doom or buffs.Silence or buffs.silence
        or buffs.Paralysis or buffs.paralysis
end

local function emergency_priority(job)
    if recovery_needed() then return true end
    if job ~= 'RDM' and job ~= 'PLD' and job ~= 'DNC'
        and job ~= 'GEO' and job ~= 'BRD'
    then
        return false
    end
    local current = player or {}
    if lowhp_active() then
        local local_floor = ATTACKER_NAMES[current.name]
            and LOWHP_ATTACKER_MIN or EMERGENCY_HPP
        return (tonumber(current.hpp) or 100) < local_floor
            or lowhp_support_floor() <= EMERGENCY_HPP
    end
    return (tonumber(current.hpp) or 100) <= EMERGENCY_HPP
        or lowest_party_hpp() <= EMERGENCY_HPP
end

local function distance(mob)
    local squared = mob and tonumber(mob.distance)
    return squared and squared >= 0 and math.sqrt(squared) or nil
end

local function action_range(mob, action)
    local size = math.max(0,
        math.min(MAX_MODEL_SIZE, tonumber(mob and mob.model_size) or 0))
    return (tonumber(action.range) or 0) + size
end

local function action_recast_ready(action, action_resource)
    if action.kind == 'spell' then
        local recasts = windower.ffxi.get_spell_recasts() or {}
        local value = tonumber(recasts[action_resource.recast_id
            or action_resource.id]) or 0
        return value < (tonumber(spell_latency) or tonumber(latency) or 1)
    elseif action.kind == 'job_ability' or action.kind == 'pet_ability' then
        local recasts = windower.ffxi.get_ability_recasts() or {}
        local value = tonumber(recasts[action_resource.recast_id]) or 0
        return value < (tonumber(latency) or 1)
    end
    return true
end

local function context()
    local request = queue.request
    if not request then return nil end
    if not authorized(request.generation, tostring(request.epoch)) then
        clear('current PartyTactics authority was revoked', false)
        return nil
    end
    local now = os.clock()
    if now >= request.expires then
        clear(request.last_blocker and ('expired while '..request.last_blocker)
            or 'expired before a legal action window', true)
        return nil
    end
    local info = windower.ffxi.get_info()
    if not info or not info.logged_in or not AMBUSCADE_ZONES[info.zone]
        or info.zone ~= request.zone or dead() or local_job() ~= request.job
        or local_subjob() ~= EXPECTED_SUBJOBS[request.job]
    then
        clear('zone, life, job, or login state changed', false)
        binding = nil
        return nil
    end
    local action = ACTIONS[request.job]
        and ACTIONS[request.job][request.semantic] or nil
    if not action then
        clear('fixed action mapping disappeared', true)
        return nil
    end
    if action.requires_lowhp_guard
        and not matching_lowhp_guard(request.encounter_id,
            request.generation, request.epoch)
    then
        clear_lowhp_recovery('low-HP authority ended', request.encounter_id)
        return nil
    end
    local boss = windower.ffxi.get_mob_by_id(request.encounter_id)
    if not boss then
        request.last_blocker = 'exact Bigwig entity is not visible'
        return request, nil, nil, action
    end
    if not exact_boss(boss, request) then
        clear('exact Bigwig entity died or changed', false)
        binding = nil
        return nil
    end
    local boss_claim = party_claimed(boss)
    if not boss_claim and ((tonumber(boss.claim_id) or 0) ~= 0
        or not action.allow_unclaimed)
    then
        clear('Bigwig is not under permitted encounter claim', false)
        return nil
    end
    local subject
    if action.party_subjects then
        subject = party_subject_by_id(request.subject_id,
            action.party_subjects, request.subject_name,
            request.subject_index)
    else
        subject = windower.ffxi.get_mob_by_id(request.subject_id)
    end
    if not subject then
        if action.party_subjects then
            clear('exact party subject died, changed, or left the party', false)
            return nil
        end
        request.last_blocker = 'exact subject entity is not visible'
        return request, boss, nil, action
    end
    if action.party_subjects and not subject
        or not action.party_subjects
            and (not exact_entity(subject, request.subject_name,
                request.subject_id, request.subject_index)
                or not associated_subject(boss, subject))
    then
        clear('exact subject died, changed, or left encounter authority', false)
        return nil
    end
    if action.subjects and not action.subjects[subject.name]
        or action.party_subjects and not action.party_subjects[subject.name]
    then
        clear('subject identity is not allowed for this semantic', false)
        return nil
    end
    return request, boss, subject, action
end

local function status_satisfied(action)
    if action.status == 'food' then return has_buff(FOOD_BUFF_ID) end
    if action.status == 'cait-sith' then return cait_sith() ~= nil end
    if action.shadow_min then return copy_images() >= action.shadow_min end
    return false
end

local function nonbusy_blocker(request, subject, action, action_resource)
    if not subject then return 'waiting for the exact subject entity' end
    if not action_resource then return 'fixed action resource is unavailable' end
    if not learned(action) then return action.name..' is unavailable' end
    if action.requires_indi_fury and not has_buff(INDI_FURY_BUFF_ID) then
        return 'waiting for exact Indi-Fury status (buff 549)'
    end
    if action.requires_clarion and not has_buff(CLARION_BUFF_ID) then
        return 'Clarion Call is not active; three-song baseline remains valid'
    end
    if action.requires_food and not has_buff(FOOD_BUFF_ID) then
        return 'waiting for confirmed Grape Daifuku food status'
    end
    if action.requires_shadow and copy_images() < 1 then
        return 'waiting for a live Copy Image status'
    end
    if action.requires_pet and not cait_sith() then
        return 'waiting for Cait Sith'
    end
    if action.target == 'enemy' or action.target == 'party' then
        local actual, maximum = distance(subject), action_range(subject, action)
        if not actual or actual > maximum then
            return ('exact subject is outside %.1fy range'):format(maximum)
        end
    end
    local current = player or {}
    if action.kind == 'weaponskill' and current.status ~= 'Engaged' then
        return 'waiting for combat engagement'
    end
    if action.min_tp and (tonumber(current.tp) or 0) < action.min_tp then
        return ('waiting for %d TP'):format(action.min_tp)
    end
    if (action.kind == 'spell' or action.kind == 'pet_ability')
        and (tonumber(current.mp) or 0)
            < (tonumber(action_resource.mp_cost) or 0)
    then
        return 'insufficient MP for '..action.name
    end
    if not action_recast_ready(action, action_resource) then
        return action.name..' is on recast'
    end
    if action.kind == 'spell' and type(silent_can_use) == 'function'
        and not function_true('silent_can_use', action.id)
    then
        return action.name..' is blocked by spell status/access'
    end
    if (action.kind == 'job_ability' or action.kind == 'pet_ability')
        and function_true('silent_check_amnesia')
    then
        return 'amnesia prevents '..action.name
    end
    if moving then return 'character is moving' end
    if function_true('silent_check_disable') then
        return 'character is incapacitated'
    end
    if recovery_needed() then return 'status recovery has priority' end
    if not action.recovery and emergency_priority(request.job) then
        return 'emergency healing has priority'
    end
    if os.clock() < (request.next_attempt or 0) then
        return 'bounded retry backoff'
    end
    return nil
end

local function busy_blocker()
    if type(midaction) == 'function' and midaction() then
        return 'another action is in progress'
    end
    local now = os.clock()
    if type(tickdelay) == 'number' and now < tickdelay then
        return 'GearSwap tick delay'
    end
    if type(next_cast) == 'number' and now < next_cast then
        return 'current action recovery'
    end
    return nil
end

local function evaluate()
    local request, _, subject, action = context()
    if not request then return nil, nil, nil, 'idle' end
    if status_satisfied(action) then
        queue.completed = queue.completed + 1
        clear(action.name..' status observed', false)
        return nil, nil, nil, 'idle'
    end
    if action.offense and action.requires_shadow and copy_images() < 1 then
        clear('Copy Image was lost before offense dispatched', false)
        return nil, nil, nil, 'idle'
    end
    if action.offense and action.requires_food and not has_buff(FOOD_BUFF_ID)
    then
        clear('Food status was lost before offense dispatched', false)
        return nil, nil, nil, 'idle'
    end
    if action.offense and not lowhp_offense_ready() then
        request.last_blocker = 'party health is below the offense floor'
        return request, subject, action, 'blocked'
    end
    local now = os.clock()
    if request.inflight_until then
        if now < request.inflight_until then
            request.last_blocker = 'awaiting action result'
            return request, subject, action, 'inflight'
        end
        request.inflight_until = nil
        request.dispatch_token_until = nil
        request.next_attempt = now + RETRY_DELAY
        if request.attempts >= action.max_attempts then
            clear(('no result after %d attempt(s)'):format(request.attempts),
                true)
            return nil, nil, nil, 'idle'
        end
    end
    local action_resource = resource(action)
    local blocker = nonbusy_blocker(request, subject, action, action_resource)
    if blocker then
        request.last_blocker = blocker
        return request, subject, action, 'blocked'
    end
    local busy = busy_blocker()
    if busy then
        request.last_blocker = busy
        return request, subject, action, 'busy'
    end
    request.last_blocker = nil
    return request, subject, action, 'ready'
end

local function dispatch(request, action)
    local now = os.clock()
    request.attempts = request.attempts + 1
    request.inflight_until = now + RESULT_TIMEOUT
    request.dispatch_token_until = now + DISPATCH_TOKEN
    request.last_result = 'awaiting action result'
    local target = action.target == 'self'
        and '<me>' or tostring(request.subject_id)
    windower.chat.input(action.command..' "'..action.name..'" '..target)
    local old_delay = type(tickdelay) == 'number' and tickdelay or 0
    tickdelay = math.max(old_delay, now + TICK_DELAY)
    queue.dispatched = queue.dispatched + 1
    queue.last_result = action.name..' dispatched'
    return true
end

local function poll()
    local request, _, action, state = evaluate()
    if not request then return false end
    if state == 'ready' then return dispatch(request, action) end
    return state == 'busy' or state == 'inflight'
end

local function make_candidate(encounter_id, subject_id, action)
    local info = windower.ffxi.get_info()
    local boss = windower.ffxi.get_mob_by_id(encounter_id)
    local subject
    if action and action.party_subjects then
        subject = party_subject_by_id(subject_id, action.party_subjects)
    else
        subject = windower.ffxi.get_mob_by_id(subject_id)
    end
    if not info or not info.logged_in or not AMBUSCADE_ZONES[info.zone]
        or not boss or not subject
        or not exact_entity(boss, BOSS, encounter_id, boss.index)
        or not action.party_subjects and (
            not exact_entity(subject, subject.name, subject_id, subject.index)
            or not ALL_SUBJECTS[subject.name])
    then
        return nil, 'exact live Ambuscade entity is required'
    end
    return {
        zone=info.zone,
        encounter_id=encounter_id, encounter_index=boss.index,
        subject_id=subject_id, subject_index=subject.index,
        subject_name=subject.name,
    }, boss, subject
end

local function set_binding(candidate, generation, epoch)
    binding = {
        zone=candidate.zone,
        encounter_id=candidate.encounter_id,
        encounter_index=candidate.encounter_index,
        generation=generation,
        epoch=epoch,
    }
end

local function set_lowhp_control(enabled, encounter_value, generation,
    epoch_value)
    local ok, epoch = authorized(generation, epoch_value)
    local encounter_id = uint32(encounter_value)
    if not ok or not encounter_id then
        queue.rejected = queue.rejected + 1
        return false, 'exact encounter and current authority are required'
    end
    if not enabled then
        if not lowhp_guard or lowhp_guard.encounter_id == encounter_id then
            lowhp_guard = nil
            clear_lowhp_recovery('low-HP authority cleared', encounter_id)
            return true, 'low-HP guard cleared'
        end
        queue.rejected = queue.rejected + 1
        return false, 'low-HP guard belongs to another encounter'
    end
    local info = windower.ffxi.get_info()
    local boss = windower.ffxi.get_mob_by_id(encounter_id)
    if not info or not info.logged_in or not AMBUSCADE_ZONES[info.zone]
        or not boss or not exact_entity(
            boss, BOSS, encounter_id, boss.index)
        or not party_claimed(boss)
    then
        queue.rejected = queue.rejected + 1
        return false, 'live party-claimed Bigwig authority is required'
    end
    lowhp_guard = {
        zone=info.zone, encounter_id=encounter_id,
        encounter_index=boss.index, generation=generation, epoch=epoch,
        expires=os.clock() + LOWHP_CONTROL_TTL,
    }
    set_binding(lowhp_guard, generation, epoch)
    if local_job() == 'PLD' and has_buff(MAJESTY_BUFF_ID)
        and windower.ffxi
        and type(windower.ffxi.cancel_buff) == 'function'
    then
        pcall(windower.ffxi.cancel_buff, MAJESTY_BUFF_ID)
    end
    return true, 'low-HP guard refreshed'
end

local function reserve(semantic, encounter_value, generation, epoch_value,
    request_token, subject_value)
    local ok, epoch = authorized(generation, epoch_value)
    if not ok then
        queue.rejected = queue.rejected + 1
        return false, 'current-generation PartyTactics authority is required'
    end
    local job = local_job()
    local action = ACTIONS[job] and ACTIONS[job][semantic] or nil
    if not action then
        queue.rejected = queue.rejected + 1
        return false, tostring(job)..' cannot perform '..tostring(semantic)
    end
    if request_token ~= nil and (type(request_token) ~= 'string'
        or #request_token < 1 or #request_token > 64
        or request_token:match('^[a-z0-9][a-z0-9_-]*$') == nil)
    then
        queue.rejected = queue.rejected + 1
        return false, 'invalid bounded request token'
    end
    local encounter_id = uint32(encounter_value)
    local subject_id = subject_value and uint32(subject_value) or encounter_id
    if not encounter_id or not subject_id then
        queue.rejected = queue.rejected + 1
        return false, 'encounter and subject IDs must be uint32 integers'
    end
    local candidate, boss, subject = make_candidate(
        encounter_id, subject_id, action)
    if not candidate
        or not action.party_subjects and (
            not action.subjects and subject_id ~= encounter_id
            or action.subjects and not action.subjects[subject.name]
            or not associated_subject(boss, subject))
        or not party_claimed(boss)
            and ((tonumber(boss.claim_id) or 0) ~= 0
                or not action.allow_unclaimed)
    then
        queue.rejected = queue.rejected + 1
        return false, 'subject is not part of the exact authorized Bigwig life'
    end
    if action.requires_lowhp_guard
        and not matching_lowhp_guard(encounter_id, generation, epoch)
    then
        queue.rejected = queue.rejected + 1
        return false, 'exact low-HP encounter authority is required'
    end
    set_binding(candidate, generation, epoch)

    if action.status and status_satisfied(action)
        or action.shadow_min and copy_images() >= action.shadow_min
    then
        return true, action.name..' state already confirmed'
    end

    local action_resource = resource(action)
    if action.opportunistic then
        if not action_resource or not learned(action)
            or action.requires_clarion and not has_buff(CLARION_BUFF_ID)
            or not action_recast_ready(action, action_resource)
        then
            return true, 'opportunistic action unavailable; baseline continues'
        end
    elseif not action_resource or not learned(action) then
        queue.rejected = queue.rejected + 1
        return false, action.name..' is unavailable'
    end
    if action.requires_food and not has_buff(FOOD_BUFF_ID)
        or action.requires_shadow and copy_images() < 1
    then
        -- Do not let a blocked damage request occupy the queue needed by the
        -- automatic food/shadow preparation heartbeat.
        return false, 'local food or shadow prerequisite is not confirmed'
    end

    local existing = queue.request
    if existing and existing.encounter_id == encounter_id
        and existing.encounter_index == candidate.encounter_index
        and existing.subject_id == subject_id
        and existing.subject_index == candidate.subject_index
        and existing.semantic == semantic
        and existing.generation == generation and existing.epoch == epoch
    then
        return true, 'already queued'
    end
    if existing then
        if existing.inflight_until then
            queue.rejected = queue.rejected + 1
            return false, 'another fixed action is already in flight'
        end
        local old = ACTIONS[existing.job]
            and ACTIONS[existing.job][existing.semantic] or nil
        if not old or action.priority <= old.priority then
            queue.rejected = queue.rejected + 1
            return false, 'another fixed action is already queued'
        end
        clear('preempted by higher-priority '..semantic, false)
    end

    local current, live = local_player()
    local player_id = tonumber(current and current.id)
        or tonumber(live and live.id)
    if action.target == 'self' and not player_id then
        queue.rejected = queue.rejected + 1
        return false, 'local character identity is unavailable'
    end
    local now = os.clock()
    queue.request = {
        semantic=semantic, job=job, generation=generation, epoch=epoch,
        zone=candidate.zone,
        encounter_id=encounter_id,
        encounter_index=candidate.encounter_index,
        subject_id=subject_id,
        subject_index=candidate.subject_index,
        subject_name=candidate.subject_name,
        result_id=action.target == 'self' and player_id or subject_id,
        request_token=request_token,
        created=now, expires=now + action.ttl,
        attempts=0, next_attempt=0, last_result='queued',
    }
    queue.accepted = queue.accepted + 1
    queue.last_result = semantic..' queued'
    return true, 'queued'
end

local function cancel_request(encounter_value, generation, epoch_value)
    local ok = authorized(generation, epoch_value)
    local encounter_id = uint32(encounter_value)
    if not ok or not encounter_id then
        queue.rejected = queue.rejected + 1
        return false, 'exact encounter and current authority are required'
    end
    local request = queue.request
    if request and request.encounter_id ~= encounter_id then
        queue.rejected = queue.rejected + 1
        return false, 'cancel does not match queued encounter'
    end
    clear('profile cancelled', false)
    if binding and binding.encounter_id == encounter_id then binding = nil end
    return true, 'cancelled'
end

local function shadow_heartbeat()
    local job = local_job()
    if (job ~= 'COR' and job ~= 'DNC' and job ~= 'PLD')
        or queue.request or not binding
        or copy_images() >= 2 or not capability
    then
        return false
    end
    local info = windower.ffxi.get_info()
    local boss = windower.ffxi.get_mob_by_id(binding.encounter_id)
    if not info or info.zone ~= binding.zone or not AMBUSCADE_ZONES[info.zone]
        or not boss or not exact_entity(boss, BOSS,
            binding.encounter_id, binding.encounter_index)
        or capability.generation ~= binding.generation
        or capability.epoch ~= binding.epoch
    then
        binding = nil
        return false
    end
    local ni = ACTIONS[job]['shadow-ni']
    local ni_resource = resource(ni)
    local semantic = ni_resource and learned(ni)
        and action_recast_ready(ni, ni_resource) and 'shadow-ni'
        or 'shadow-ichi'
    local accepted = reserve(semantic, tostring(binding.encounter_id),
        binding.generation, tostring(binding.epoch), nil,
        tostring(binding.encounter_id))
    if accepted then return poll() end
    return false
end

local RECOVERY_ITEMS = {
    ['Echo Drops']=true, Remedy=true, Panacea=true, ['Holy Water']=true,
}
local RECOVERY_SPELLS = {
    Cure=true, Erase=true, Poisona=true, Paralyna=true, Silena=true,
    Blindna=true, Stona=true, Viruna=true, Cursna=true,
}

local function spell_name(spell)
    return spell and (spell.english or spell.en or spell.name) or nil
end

local function emergency_action(spell)
    local name = spell_name(spell)
    if not name then return false end
    if spell.action_type == 'Item' and RECOVERY_ITEMS[name] then return true end
    if name:match('^Cure [IVX]+$') or name:match('^Cura')
        or RECOVERY_SPELLS[name]
    then
        return true
    end
    if local_job() == 'DNC' and (name:match('^Curing Waltz')
        or name:match('^Divine Waltz') or name == 'Healing Waltz'
        or name == 'No Foot Rise' or name == 'Reverse Flourish')
    then
        return true
    end
    return local_job() == 'RDM' and name == 'Convert'
end

local function own_dispatch(spell, phase)
    local request = queue.request
    if not request or not request.inflight_until or not spell then return false end
    local action = ACTIONS[request.job]
        and ACTIONS[request.job][request.semantic] or nil
    if not action or tonumber(spell.id) ~= action.id then return false end
    local target_id = spell.target and tonumber(spell.target.id) or nil
    return target_id == request.result_id
        or os.clock() <= (request.dispatch_token_until or 0)
            and (phase == 'pretarget' or target_id == nil)
end

local function restorative_hp_action(spell)
    local name = spell_name(spell)
    if not name then return false, false end
    local area = name:match('^Curaga') or name:match('^Cura')
        or name:match('^Divine Waltz')
    local targeted = name == 'Cure' or name == 'Full Cure'
        or name:match('^Cure [IVX]+$') or name:match('^Regen')
        or name:match('^Curing Waltz')
    return targeted ~= nil and targeted ~= false, area ~= nil and area ~= false
end

local function lowhp_blocks_heal(spell)
    if not lowhp_active() then return false end
    if spell_name(spell) == 'Majesty' then return true end
    local targeted, area = restorative_hp_action(spell)
    if area then return true end
    if not targeted then return false end
    if local_job() == 'PLD' and has_buff(MAJESTY_BUFF_ID) then return true end
    local target = type(spell) == 'table' and spell.target or nil
    if type(target) == 'table' and ATTACKER_NAMES[target.name] then
        return true
    end
    local target_id = type(target) == 'table' and tonumber(target.id) or nil
    return target_id ~= nil
        and party_subject_by_id(target_id, ATTACKER_NAMES) ~= nil
end

local function blocks_action(spell, phase)
    if own_dispatch(spell, phase) then return false end
    if lowhp_blocks_heal(spell) then return true end
    local request, _, _, state = evaluate()
    if not request or emergency_action(spell) then
        return false
    end
    if request.job == 'DNC' and request.semantic ~= 'food' then return true end
    return state == 'ready' or state == 'busy' or state == 'inflight'
end

function M.activate()
    return true
end

function M.pre_tick()
    shadow_heartbeat()
    return poll()
end

function M.user_job_tick()
    shadow_heartbeat()
    return poll()
end

function M.filter_pretarget(spell, spellMap, eventArgs)
    return blocks_action(spell, 'pretarget')
end

function M.filter_precast(spell, spellMap, eventArgs)
    return blocks_action(spell, 'precast')
end

function M.job_aftercast(spell)
    local request = queue.request
    if not request or not request.inflight_until or not spell then return end
    local action = ACTIONS[request.job]
        and ACTIONS[request.job][request.semantic] or nil
    if action and tonumber(spell.id) == action.id and spell.interrupted then
        request.inflight_until = nil
        request.dispatch_token_until = nil
        if request.attempts >= action.max_attempts then
            clear('interrupted after bounded attempts', true)
        else
            request.next_attempt = os.clock() + RETRY_DELAY
        end
    end
end

function M.handle_action(controller, semantic, arguments)
    if type(controller) ~= 'string' or controller:lower() ~= M.controller then
        queue.rejected = queue.rejected + 1
        return false, 'unsupported controller'
    end
    if type(semantic) ~= 'string' then
        queue.rejected = queue.rejected + 1
        return false, 'semantic is required'
    end
    local requested = semantic:lower()
    local args = type(arguments) == 'table' and arguments or {}
    if requested == 'probe' then
        local ok, reason = probe(args[1], args[2], args[3])
        if not ok then chat(123, 'capability probe rejected: '..reason..'.') end
        return ok, reason
    elseif requested == 'cancel' then
        return cancel_request(args[1], args[2], args[3])
    elseif requested == 'status' then
        return true, M.status()
    elseif requested == 'lowhp-on' or requested == 'lowhp-off' then
        return set_lowhp_control(requested == 'lowhp-on',
            args[1], args[2], args[3])
    end
    local token = args[4]
    local subject = args[5]
    if token == '-' and subject ~= nil then token = nil end
    local ok, reason = reserve(requested, args[1], args[2], args[3],
        token, subject)
    if not ok then
        chat(123, 'request rejected: '..tostring(reason)..'.')
        return false, reason
    end
    poll()
    return true, reason
end

function M.status()
    local request = queue.request
    local current = request and (request.semantic..'#'
        ..tostring(request.subject_id)) or 'idle'
    return ('queue=%s accepted=%d dispatched=%d completed=%d rejected=%d')
        :format(current, queue.accepted, queue.dispatched,
            queue.completed, queue.rejected)
end

function M.deactivate(reason)
    report_lost()
    clear(reason or 'adapter deactivated', false)
    return true
end

function M.file_unload()
    return M.deactivate('GearSwap job file unloaded')
end

function M.action_event(packet)
    local request = queue.request
    if not request or not request.inflight_until or type(packet) ~= 'table' then
        return
    end
    local validated, _, subject, action = context()
    if validated ~= request or not subject or not action then return end
    local current = windower.ffxi.get_player()
    local pet_entity = cait_sith()
    local actor_ok = current and tonumber(packet.actor_id) == tonumber(current.id)
    if action.kind == 'pet_ability' and pet_entity then
        actor_ok = actor_ok
            or tonumber(packet.actor_id) == tonumber(pet_entity.id)
    end
    local category_ok = action.result_categories
        and action.result_categories[tonumber(packet.category)]
        or tonumber(packet.category) == action.category
    local param_ok = action.result_ids
        and action.result_ids[tonumber(packet.param)]
        or tonumber(packet.param) == action.id
    if not actor_ok or not category_ok or not param_ok then return end
    local function packet_result(id)
        for _, target in ipairs(packet.targets or {}) do
            if tonumber(target.id) == tonumber(id) then
                return target.actions and target.actions[1] or nil
            end
        end
        return nil
    end
    for _, target in ipairs(packet.targets or {}) do
        if tonumber(target.id) == tonumber(request.result_id) then
            local result = target.actions and target.actions[1]
            if result and FAILURE_MESSAGES[tonumber(result.message)] then
                request.inflight_until = nil
                request.dispatch_token_until = nil
                request.next_attempt = os.clock() + RETRY_DELAY
                if request.attempts >= action.max_attempts then
                    clear('server rejected action after bounded attempts', true)
                end
                return
            end
            if action.kind == 'pet_ability' then
                local boss = windower.ffxi.get_mob_by_id(request.encounter_id)
                local all_adds_confirmed = boss ~= nil
                if boss then
                    for _, mob in pairs(windower.ffxi.get_mob_array() or {}) do
                        if type(mob) == 'table' and ADD_ONLY[mob.name]
                            and mob.spawn_type == 16
                            and mob.valid_target == true
                            and (tonumber(mob.hpp) or 0) > 0
                            and associated_subject(boss, mob)
                        then
                            local add_result = packet_result(mob.id)
                            if not add_result or FAILURE_MESSAGES[
                                tonumber(add_result.message)]
                            then
                                all_adds_confirmed = false
                                break
                            end
                        end
                    end
                end
                if not all_adds_confirmed then
                    request.inflight_until = nil
                    request.dispatch_token_until = nil
                    request.next_attempt = os.clock() + RETRY_DELAY
                    request.last_result = 'Mewing did not confirm every live add'
                    if request.attempts >= action.max_attempts then
                        clear('Mewing did not reach every live add', true)
                    end
                    return
                end
            end
            queue.completed = queue.completed + 1
            clear(action.name..' completed', false)
            return
        end
    end
end

function M.prerender()
    shadow_heartbeat()
    if not queue.request then return false end
    local now = os.clock()
    if now < queue.next_poll then return false end
    queue.next_poll = now + POLL_INTERVAL
    return poll()
end

function M.zone_change()
    binding = nil
    lowhp_guard = nil
    clear('zone changed', false)
end

function M.logout()
    binding = nil
    lowhp_guard = nil
    clear('logout', false)
end

function M.unload()
    return M.deactivate('GearSwap unloaded')
end

function M.status_change(new_status)
    if new_status == 2 or type(new_status) == 'string'
        and new_status:lower():find('dead', 1, true)
    then
        binding = nil
        lowhp_guard = nil
        clear('character died', false)
    end
end

return M
