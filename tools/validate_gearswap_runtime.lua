local data_root = os.getenv('GEARSWAP_TEST_ROOT')
    and (os.getenv('GEARSWAP_TEST_ROOT'):gsub('\\', '/')..'/data/')
    or [[C:\Program Files (x86)\Windower\addons\GearSwap\data\]]

local function copy(value, seen)
    if type(value) ~= 'table' then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local result = {}
    seen[value] = result
    for key, item in pairs(value) do result[key] = copy(item, seen) end
    return result
end

function set_combine(...)
    local result = {}
    for index = 1, select('#', ...) do
        local source = select(index, ...)
        if type(source) == 'table' then
            for key, value in pairs(source) do result[key] = copy(value) end
        end
    end
    return result
end

local mode_methods = {}
function mode_methods:options(...)
    self.values = {...}
    if self.value == nil then self.value = self.values[1] end
end
function mode_methods:set(value) self.value = value end
function mode_methods:reset() if self.values then self.value = self.values[1] end end
function mode_methods:contains(value)
    for _, item in ipairs(self.values or {}) do if item == value then return true end end
    return false
end
function mode_methods:cycle() end
function mode_methods:toggle() end

local function mode(default)
    return setmetatable({value=default, current=default, values={default}}, {__index=mode_methods})
end

function M(value)
    if type(value) == 'table' then
        local first
        for index, item in ipairs(value) do if index > 0 then first = item break end end
        local result = mode(first)
        result:options(table.unpack(value))
        return result
    end
    return mode(value)
end

state = setmetatable({}, {__index=function(table_value, key)
    local value = mode('None')
    rawset(table_value, key, value)
    return value
end})

sets = {
    precast={JA={},WS={},RA={},FC={},Waltz={},Item={}},
    midcast={RA={},Pet={}},
    idle={}, resting={}, engaged={}, defense={}, buff={}, element={},
    passive={}, weapons={}, TreasureHunter={}, Reraise={},
}
gear = {}
info = {}
options = {}
classes = {CustomMeleeGroups={}}
empty = 'empty'
local runtime_job = arg[1] and arg[1]:match('_([A-Z]+)_Gear%.lua$') or 'PLD'
player = {
    sub_job=os.getenv('GEARSWAP_SUBJOB') or 'WAR',
    main_job=runtime_job, mp=1000, status='Idle',
}
world = {area='Test'}
buffactive = {}
data = {areas={cities={contains=function() return false end}}}

local runtime_owned = {}
for name in (os.getenv('GEARSWAP_OWNED') or ''):gmatch('[^|]+') do
    runtime_owned[name:lower()] = true
end
function item_available(name)
    return type(name) == 'string' and runtime_owned[name:lower()] or false
end
function item_owned(name) return item_available(name) end
function send_command() end
function enable() end
function disable() end
function add_to_chat() end
local last_equipped
function equip(equip_set) last_equipped = copy(equip_set) end
function update_defense_mode() end
function select_default_macro_book() end
function set_macro_page() end
function include(path)
    local normalized = path:gsub('/', '\\')
    if normalized:find('PartyStart', 1, true)
        or normalized:find('PartyOpsTrace', 1, true)
        or normalized:find('PartyTactics', 1, true)
    then
        return
    end
    dofile(data_root..normalized)
end

-- Optional arguments model the follower character-global layer that is loaded
-- before the character/job file in Sel-Include.  A '-' placeholder permits a
-- caller to request arg[4] dump mode without loading either optional layer.
local follower_file = arg[2] ~= '-' and arg[2] or nil
local profile_file = arg[3] ~= '-' and arg[3] or nil
if follower_file then dofile(follower_file) end
if profile_file then dofile(profile_file) end
dofile(arg[1])
if user_setup then user_setup() end
if character_setup then character_setup() end
if follower_file and follower_gear_installed then
    error('stale FollowerGear postprocessor was installed')
end
if init_gear_sets then init_gear_sets() end

if arg[4] == 'cor-modes' then
    assert(sets.weapons.RostamC.sub == 'Nusku Shield',
        'COR RostamC mode must use a COR-legal shield')
    assert(sets.weapons.Naegling.main == 'Naegling'
        and sets.weapons.Naegling.sub == 'Nusku Shield',
        'COR Naegling mode must use Naegling with a COR-legal shield')
    assert(sets.weapons.DualSavage.main == 'Naegling'
        and sets.weapons.DualSavage.sub.name == "Gleti's Knife",
        'DualSavage must equip Naegling and Gleti\'s Knife')
    assert(sets.weapons.DualEvis.main == 'Tauret'
        and sets.weapons.DualEvis.sub.name == "Gleti's Knife",
        'DualEvis must equip Tauret and Gleti\'s Knife')
    assert(sets.weapons.DualSavage.range == empty,
        'DualSavage must deliberately empty range')
    state.Weapons:set('DualSavage')
    local melee = extra_user_customize_melee_set({ammo='Aurgelmir Orb +1'})
    local idle = extra_user_customize_idle_set({ammo='Staunch Tathlum +1'})
    assert(melee.ammo == 'Aurgelmir Orb +1',
        'range-empty DualSavage must retain melee stat ammo')
    assert(idle.ammo == 'Staunch Tathlum +1',
        'range-empty DualSavage must retain idle stat ammo')

    state.Weapons:set('DualLastStandRanged')
    melee = extra_user_customize_melee_set({ammo='Aurgelmir Orb +1'})
    idle = extra_user_customize_idle_set({ammo='Staunch Tathlum +1'})
    assert(melee.ammo == gear.RAbullet,
        'gun-bearing melee state must use a compatible bullet')
    assert(idle.ammo == gear.RAbullet,
        'gun-bearing idle state must use a compatible bullet')

    last_equipped = nil
    user_job_post_precast({type='Magic', action_type='Magic'}, nil, {})
    assert(last_equipped and last_equipped.ammo == gear.RAbullet,
        'gun-bearing non-ranged actions must preserve compatible ammo')
    last_equipped = nil
    user_job_post_precast({
        type='WeaponSkill', action_type='Ability', skill='Marksmanship',
    }, nil, {})
    assert(last_equipped == nil,
        'marksmanship actions must retain their action-selected bullet')

    if player.sub_job == 'THF' then
        assert(state.TreasureMode.value == 'Tag',
            'COR/THF must default to GearSwap first-action TH tagging')
        assert(sets.TreasureHunter.waist == 'Chaac Belt',
            'COR/THF tag must include Chaac Belt')
        assert(sets.TreasureHunter.ammo == nil,
            'gun-bearing COR TH set must not lock stat ammo over bullets')
        print('cor-th-tag-ok')
    end
    print('cor-mode-ammo-ok')
end

if arg[4] == 'dump' then
    local slot_keys = {
        main=true, sub=true, range=true, ranged=true, ammo=true,
        head=true, body=true, hands=true, legs=true, feet=true,
        neck=true, waist=true, back=true,
        left_ear=true, right_ear=true, ear1=true, ear2=true,
        left_ring=true, right_ring=true, ring1=true, ring2=true,
    }
    local seen = {}
    local function dump(candidate, path)
        if type(candidate) ~= 'table' or seen[candidate] then return end
        seen[candidate] = true
        for key, value in pairs(candidate) do
            if slot_keys[key] then
                local name = type(value) == 'table' and value.name or value
                if type(name) == 'string' and name ~= 'empty' then
                    print('set-item\t'..path..'.'..tostring(key)..'\t'..name)
                end
            elseif type(value) == 'table' and not value.name then
                dump(value, path..'.'..tostring(key))
            end
        end
    end
    dump(sets, 'sets')
end
print('runtime-ok: '..arg[1])
