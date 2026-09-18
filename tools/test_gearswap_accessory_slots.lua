-- Offline regression: real character/Common gear definitions, FindAll ownership,
-- and the installed GearSwap priority iterator. This is not a live packet test.
local script_path = (arg[0] or ''):gsub('\\', '/')
local workspace = (os.getenv('FFXI_WORKSPACE')
    or script_path:match('^(.*)/tools/[^/]+$') or '.')..'/'
local gs_root = assert(os.getenv('GEARSWAP_TEST_ROOT'), 'Supply GEARSWAP_TEST_ROOT'):gsub('\\', '/')
local windower_root = assert(gs_root:match('^(.*)/addons/[^/]+/?$'), 'GearSwapRoot must be under a Windower addons folder')..'/'
local data_root = gs_root..'/data/'
local baseline_dir = arg[1]
assert(load(assert(os.getenv('GEARSWAP_ACCESSORY_CORE')), 'installed-priority-code'))()

local resources = dofile(windower_root..[[res\items.lua]])
local slot_names = {
    [0]='main', 'sub', 'range', 'ammo', 'head', 'body', 'hands', 'legs',
    'feet', 'neck', 'waist', 'left_ear', 'right_ear', 'left_ring', 'right_ring', 'back',
}
local slots = {}
for id, name in pairs(slot_names) do slots[name] = id end
for alias, name in pairs({
    ranged='range', ear1='left_ear', ear2='right_ear', lear='left_ear', rear='right_ear',
    learring='left_ear', rearring='right_ear', ring1='left_ring', ring2='right_ring',
    lring='left_ring', rring='right_ring',
}) do slots[alias] = slots[name] end

local function serialize(value, omit_priority)
    if type(value) ~= 'table' then return type(value)..':'..tostring(value) end
    local parts = {}
    for key, child in pairs(value) do
        if not (omit_priority and key == 'priority') then
            parts[#parts+1] = serialize(key)..'='..serialize(child, omit_priority)
        end
    end
    table.sort(parts)
    return '{'..table.concat(parts, ',')..'}'
end

local function item(value, omit_priority)
    if type(value) == 'string' then value = {name=value} end
    return serialize(value, omit_priority)
end

local function flatten(root)
    local result = {}
    local function visit(node, path, parents)
        assert(not parents[node], 'Cyclic gear-set table: '..path)
        parents[node] = true
        local equipped = {}
        result[path] = equipped
        for key, value in pairs(node) do
            local slot = slots[key]
            if slot then
                assert(not equipped[slot] or item(equipped[slot]) == item(value),
                    'Conflicting slot aliases at '..path..'.'..tostring(key))
                equipped[slot] = value
            elseif type(value) == 'table' and not value.name then
                visit(value, path..'.'..tostring(key), parents)
            end
        end
        parents[node] = nil
    end
    visit(root, 'sets', {})
    return result
end

local function available_items(character)
    local inventory = dofile(windower_root..[[addons\findAll\data\]]..character..'.lua')
    local available = {}
    for bag, content in pairs(inventory) do
        -- Key items and storage-slip IDs are different namespaces, not equipment.
        if type(content) == 'table' and (bag == 'inventory' or bag:match('^wardrobe%d*$')) then
            for id, count in pairs(content) do
                local resource = resources[tonumber(id)]
                if resource and type(count) == 'number' and count > 0 then
                    available[resource.en:lower()] = true
                end
            end
        end
    end
    return available
end

local function load_profile(character, job, directory)
    local filename = character..'_'..job..'_Gear.lua'
    local owned = available_items(character)
    local profile = (directory and directory..'\\' or data_root..character..'\\')..filename
    arg = {profile, '-', '-'}
    dofile(workspace..[[tools\validate_gearswap_runtime.lua]])
    -- Seed the character-wide item layer, then rebuild with inventory-backed
    -- Common selectors. The general harness deliberately omits these by default.
    sets.precast.Item = sets.precast.Item or {}
    dofile(data_root..character..'\\'..character..'-Items.lua')
    function item_available(name) return type(name) == 'string' and owned[name:lower()] or false end
    item_owned = item_available
    user_setup()
    character_setup()
    init_gear_sets()
    return {tree=sets, flat=flatten(sets), owned=owned}
end

local function pair_content(set, left)
    local pair = {item(set[left], true), item(set[left+1], true)}
    table.sort(pair)
    return table.concat(pair, '|')
end

local function compare_gear(before, after, character)
    local set_count, slot_count = 0, 0
    for path, old_set in pairs(before.flat) do
        local new_set = assert(after.flat[path], 'Lost set: '..path)
        set_count = set_count + 1
        for slot = 0, 15 do
            if old_set[slot] then slot_count = slot_count + 1 end
            if slot < 11 or slot > 14 then
                assert(item(old_set[slot], true) == item(new_set[slot], true),
                    'Changed gear/augment: '..path..'.'..slot_names[slot])
            end
        end
        for _, left in ipairs({11,13}) do
            assert(pair_content(old_set, left) == pair_content(new_set, left),
                'Changed accessory pair/augment: '..path..'.'..slot_names[left])
        end
    end
    for path in pairs(after.flat) do assert(before.flat[path], 'Unexpected new set: '..path) end
    print(character..': preserved all gear/augments across '..set_count..' set tables / '..slot_count..' assignments')
end

local function transition(from, to, left, watched)
    local current = {[left]=expand_entry(from[left]), [left+1]=expand_entry(from[left+1])}
    local order = Priorities.new()
    for slot = left, left+1 do
        local name, priority = expand_entry(to[slot])
        if name and name ~= current[slot] then order[slot] = priority end
    end
    local hazards = {}
    for slot in order:it() do
        local name = expand_entry(to[slot])
        local opposite = left + (slot == left and 1 or 0)
        if watched[name] and current[opposite] == name then
            hazards[#hazards+1] = name
        else
            current[slot] = name
        end
    end
    return hazards
end

local function variants(snapshot, left)
    local result, seen = {}, {}
    local function add(set, path)
        if not set[left] or not set[left+1] then return end
        local key = item(set[left])..'|'..item(set[left+1])
        if seen[key] then return end
        seen[key] = true
        result[#result+1] = {set=set, path=path}
    end
    for path, set in pairs(snapshot.flat) do add(set, path) end
    -- Relevant overlays may use ring1/ring2 aliases; flatten canonicalizes them
    -- before merging, just as native GearSwap normalizes user slot names.
    for _, overlay_path in ipairs({'sets.Sheltered', 'sets.buff.Doom', 'sets.MagicBurst', 'sets.Self_Healing'}) do
        local overlay = snapshot.flat[overlay_path] or {}
        for _, path in ipairs({'sets.idle','sets.midcast.Cure','sets.midcast.Cure.DT',
            'sets.midcast.Elemental Magic','sets.midcast.Elemental Magic.DT'}) do
            local base = snapshot.flat[path]
            if base then
                local merged = {}
                for slot, value in pairs(base) do merged[slot] = value end
                for slot, value in pairs(overlay) do merged[slot] = value end
                add(merged, path..' + '..overlay_path)
            end
        end
    end
    return result
end

local function check_transitions(snapshot, character, left, watched)
    local pairs_to_check = variants(snapshot, left)
    for _, from in ipairs(pairs_to_check) do
        for _, to in ipairs(pairs_to_check) do
            local failures = transition(from.set, to.set, left, watched)
            assert(#failures == 0, character..': opposite-slot conflict: '..table.concat(failures, ', ')..
                ' from '..from.path..' to '..to.path)
        end
    end
    print(character..': '..(#pairs_to_check * #pairs_to_check)..' accessory-order transitions passed (including overlays)')
end

local profiles = {
    {character='Smalls', job='RDM', watched={['Magnetic Earring']=true,['Andoaa Earring']=true}, left=11,
        anchors={['Magnetic Earring']=11,['Andoaa Earring']=12},
        old_from='sets.midcast.Enhancing Magic', old_to='sets.precast.FC', old_item='Magnetic Earring'},
    {character='Achoo', job='GEO', watched={['Murky Ring']=true,['Tamas Ring']=true,['Jhakri Ring']=true,
        ['Sheltered Ring']=true,['Metamor. Ring +1']=true,['Mujin Band']=true}, left=13,
        anchors={['Murky Ring']=13,['Jhakri Ring']=13,['Sheltered Ring']=14,['Metamor. Ring +1']=14,['Mujin Band']=13},
        old_from='sets.idle', old_to='sets.precast.FC', old_item='Murky Ring'},
}

for _, profile in ipairs(profiles) do
    local before = baseline_dir and load_profile(profile.character, profile.job, baseline_dir)
    local after = load_profile(profile.character, profile.job)
    for name in pairs(profile.watched) do
        assert(after.owned[name:lower()], profile.character..': item not in Inventory/Wardrobe: '..name)
    end
    for path, set in pairs(after.flat) do
        for slot = 11, 14 do
            local name, priority = expand_entry(set[slot])
            if profile.anchors[name] then
                assert(slot == profile.anchors[name], 'Wrong side for '..name..' at '..path)
            end
            if profile.character == 'Achoo' and name == 'Jhakri Ring' then
                assert(priority == -1, 'Missing native Jhakri priority at '..path)
            end
            if profile.character == 'Achoo' and name == 'Tamas Ring' then
                assert(priority == -2, 'Missing native Tamas priority at '..path)
            end
            if profile.character == 'Achoo' and name == 'Metamor. Ring +1' then
                assert(serialize(set[slot].augments) == serialize({'Path: A'}),
                    'Metamor must use the native Unity Path: A augment selector at '..path)
            end
        end
    end
    if profile.character == 'Achoo' then
        for _, spell in ipairs({'Cure','LightWeatherCure','LightDayCure','Curaga'}) do
            local normal = after.tree.midcast[spell]
            assert(expand_entry(normal.left_ring) == 'Tamas Ring' and expand_entry(normal.right_ring) == 'Metamor. Ring +1', spell..': wrong normal rings')
            assert(normal.DT.left_ring == 'Murky Ring' and expand_entry(normal.DT.right_ring) == 'Metamor. Ring +1', spell..': wrong DT rings')
        end
        local cursna = after.tree.midcast.Cursna
        assert(expand_entry(cursna.left_ring) == 'Jhakri Ring' and expand_entry(cursna.right_ring) == 'Tamas Ring', 'Cursna must not inherit MND cure rings')
        assert(cursna.DT.left_ring == 'Murky Ring' and expand_entry(cursna.DT.right_ring) == 'Tamas Ring', 'Cursna DT must retain defensive/enmity rings')
        for _, burst in ipairs({after.tree.MagicBurst, after.tree.RecoverBurst}) do
            assert(burst.left_ring == 'Mujin Band' and expand_entry(burst.right_ring) == 'Metamor. Ring +1', 'Burst override lost its ring pair')
        end
    end
    if before then
        compare_gear(before, after, profile.character)
        local old_failures = transition(before.flat[profile.old_from], before.flat[profile.old_to], profile.left, profile.watched)
        assert(old_failures[1] == profile.old_item, 'Regression model did not catch original '..profile.old_item..' conflict')
        if profile.character == 'Achoo' then
            local tamas = transition(before.flat['sets.precast.FC'], before.flat['sets.midcast.Cure'], 13, profile.watched)
            assert(tamas[1] == 'Tamas Ring', 'Regression model did not catch original Tamas conflict')
        end
    end
    check_transitions(after, profile.character, profile.left, profile.watched)
end
print('All accessory-slot regression tests passed.')
