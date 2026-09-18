-- Read-only integration check against the installed GearSwap parser/resolver.
-- Run in a separate Lua 5.1 runtime, with arg[1] set to the GearSwap directory.
-- No Windower client, network calls, equipment changes, or packet injection.
local gs_root = assert(arg and arg[1], 'GearSwap directory is required')
-- Small string/list helpers used by the unmodified command parser. Windower's
-- own libraries contain launcher-specific syntax that stock Lua cannot parse.
local string_methods = setmetatable({}, {__index=string})
function string_methods.split(text, separator)
    local parts = {}
    for part in (text..separator):gmatch('(.-)'..separator) do
        parts[#parts+1] = part
    end
    parts.n = #parts
    function parts:filter(predicate)
        local result = {}
        for _, part in ipairs(self) do
            if predicate(part) then result[#result+1] = part end
        end
        result.n = #result
        return result
    end
    return parts
end
debug.setmetatable('', {__index=string_methods, __unm=function(text)
    return function(value) return value ~= text end
end})

local function copy(value)
    local result = {}
    for key, entry in pairs(value) do result[key] = entry end
    return result
end

local env = setmetatable({}, {__index=_G})
local outgoing_text, selected_reads, precasts = nil, 0, {}
local caster = {id=16933034, index=170, name='Apollyon Demon',
    is_npc=true, spawn_type=16, valid_target=true, hpp=100, distance=13.2^2}
local other = {id=16933035, index=171, name='Apollyon Demon',
    is_npc=true, spawn_type=16, valid_target=true, hpp=100, distance=5^2}
local selected = other
env.player = {id=1}
env.language = 'english'
env.parse = {i={}, o={}}
env.pass_through_targs = {['<t>']=true, ['<bt>']=true}
env.unify_prefix = {['/ma']='/ma'}
env.outgoing_action_category_table = {['/ma']=3}
env.action_type_map = {['/ma']='Magic'}
env.validabils = {english={['/ma']={silence=59}}}
env.res = {spells={[59]={id=59, english='Silence', prefix='/ma',
    targets={Enemy=true}, mp_cost=16}}}
env.windower = {
    register_event=function(name, callback)
        assert(name == 'outgoing text')
        outgoing_text = callback
    end,
    debug=function() end,
    from_shift_jis=function(text) return text end,
    to_shift_jis=function(text) return text end,
    convert_auto_trans=function(text) return text end,
    ffxi={
        get_party=function() return {} end,
        get_mob_by_id=function(id)
            if id == caster.id then return copy(caster) end
            if id == other.id then return copy(other) end
        end,
        get_mob_by_target=function()
            selected_reads = selected_reads + 1
            return selected and copy(selected)
        end,
        get_mob_array=function() error('must not resolve this enemy by name') end,
    },
}
env.refresh_globals = function() end
env.copy_entry = copy
env.spell_complete = function(spell) return spell end
env.filter_pretarget = function(spell) return spell.id == 59 end
env.filter_precast = function(spell)
    return spell.target.id ~= nil and spell.target.index ~= nil
end
env.command_registry = {new_entry=function(self, spell)
    self[1] = {spell=spell}
    return 1
end}
env.initialize_arrow_offset = function() return {} end
env.assemble_action_packet = function(id, index, category, spell_id)
    return {id=id, index=index, category=category, spell_id=spell_id}
end
env.equip_sets = function(event, timestamp, spell)
    assert(event == 'precast', 'must reach the normal GearSwap precast entry point')
    local packet = env.command_registry[timestamp].proposed_packet
    assert(packet.id == caster.id and packet.index == caster.index)
    assert(packet.category == 3 and packet.spell_id == 59)
    assert(spell.target.id == caster.id and spell.target.type == 'MONSTER')
    assert(math.abs(spell.target.distance - math.sqrt(caster.distance)) < 0.001)
    precasts[#precasts+1] = spell
    return true
end

local function load_in_environment(path)
    local loader, load_error
    if setfenv then
        loader, load_error = loadfile(path)
        if loader then setfenv(loader, env) end
    else
        loader, load_error = loadfile(path, 't', env)
    end
    return assert(loader, load_error)()
end

load_in_environment(gs_root..'/targets.lua')
load_in_environment(gs_root..'/triggers.lua')
assert(outgoing_text, 'installed GearSwap did not register its command parser')

for _, distance in ipairs({13.2, 19.1, 20.9}) do
    caster.distance = distance^2
    for _, has_target in ipairs({false, true}) do
        selected = has_target and other or nil
        local command = '/ma "Silence" '..tostring(caster.id)
        assert(outgoing_text(command, command) == true,
            'GearSwap must consume the numeric-ID command, not pass it to FFXI chat')
    end
end
assert(#precasts == 6 and selected_reads == 0,
    'cast dispatch must not depend on the selected or battle target')
print('PASS installed GearSwap numeric-ID Silence: 6 parser/resolver-to-precast cases')
