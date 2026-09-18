local loader, load_error = loadfile('addons/PartyTactics/lib/action_api.lua')
assert(loader, load_error)
local module = loader()

local commands = {}
local actions, client = module.create(function(command)
    commands[#commands + 1] = command
end, function()
    return '123-456-7', 2
end)

local function expect_command(expected, operation)
    local before = #commands
    local ok, reason = operation()
    assert(ok == true, tostring(reason))
    assert(#commands == before + 1, 'accepted operation must issue once')
    assert(commands[#commands] == expected,
        ('expected %q, received %q'):format(expected, commands[#commands]))
end

local function expect_rejected(operation)
    local before = #commands
    local ok, reason = operation()
    assert(ok == false and type(reason) == 'string' and reason ~= '')
    assert(#commands == before, 'rejected operation issued a command')
end

expect_command('pc forceid 1234', function()
    return actions.combat_force(1234)
end)
expect_command('pc forceid 42', function()
    return actions.combat_force('00042')
end)
expect_command('pc forceid 4294967295', function()
    return actions.combat_force(4294967295)
end)
expect_command('pc forceopaqueid 900 Rancibus', function()
    return actions.combat_force(900, 'Rancibus')
end)
expect_command('pc forceidto 401 Barneystinson', function()
    return actions.combat_force_members(401, {'Barneystinson'})
end)
expect_command('pc forceidto 402 Kickpuncher,Barneystinson', function()
    return actions.combat_force_members(
        '000402', {'Kickpuncher','Barneystinson'})
end)
expect_command('pc stopto Dolomedes', function()
    return actions.combat_stop_members({'Dolomedes'})
end)
expect_command('pc stopto Tackleberry,Smalls', function()
    return actions.combat_stop_members({'Tackleberry','Smalls'})
end)
expect_command('pc observeid 5003', function()
    return actions.combat_observe('5003')
end)
expect_command('pc off', function()
    return actions.combat_stop()
end)

for _, invalid in ipairs({
    0, -1, 1.5, 4294967296, math.huge,
    '', '-1', '+1', '1.0', '1e3', '4294967296', '1;pc on', {}, false,
}) do
    expect_rejected(function() return actions.combat_force(invalid) end)
    expect_rejected(function() return actions.combat_observe(invalid) end)
end
expect_rejected(function() return actions.combat_force(0 / 0) end)
expect_rejected(function() return actions.combat_force(nil) end)
expect_rejected(function()
    return actions.combat_force_members(401, nil)
end)
for _, invalid in ipairs({
    {}, {'Barneystinson','barneystinson'},
    {'Barneystinson', 'Smalls;pc on'},
    {[1]='Barneystinson',[3]='Kickpuncher'},
    {'a','b','c','d','e','f','g'},
}) do
    expect_rejected(function()
        return actions.combat_force_members(401, invalid)
    end)
    expect_rejected(function()
        return actions.combat_stop_members(invalid)
    end)
end
expect_rejected(function() return actions.combat_stop_members(nil) end)
for _, invalid in ipairs({0, -1, 1.5, '1;pc on'}) do
    expect_rejected(function()
        return actions.combat_force_members(invalid, {'Barneystinson'})
    end)
end
for _, invalid in ipairs({'', ' Rancibus', 'Rancibus;pc on', {}, false}) do
    expect_rejected(function() return actions.combat_force(900, invalid) end)
end
expect_rejected(function() return actions.combat_observe(0 / 0) end)
expect_rejected(function() return actions.combat_observe(nil) end)

expect_command('input /autotarget off', function()
    return client.auto_target(false)
end)
expect_command('input /autotarget on', function()
    return client.auto_target(true)
end)
expect_command('pc engageonceid 5003', function()
    return client.engage_once('0005003')
end)
for _, invalid in ipairs({'off', 'on', 0, 1, {}}) do
    expect_rejected(function() return client.auto_target(invalid) end)
end
expect_rejected(function() return client.auto_target(nil) end)
for _, invalid in ipairs({
    0, -1, 1.5, 4294967296, math.huge,
    '', '-1', '+1', '1.0', '1e3', '4294967296', '1;pc on', {}, false,
}) do
    expect_rejected(function() return client.engage_once(invalid) end)
end

-- Existing typed action and controller behavior stays intact.
expect_command('input /ma "Silence" 4294967295', function()
    return actions.cast('Silence', '4294967295')
end)
expect_command('gs c pstartbrd sleep', function()
    return actions.controller('brd', 'sleep')
end)
expect_command('gs c pstartrdm silence 5003', function()
    return actions.controller('rdm', 'silence', '0005003')
end)
expect_command('gs c pstartrdm silence 4294967295', function()
    return actions.controller('rdm', 'silence', 4294967295)
end)
expect_command('gs c ptgs action genmei lead 1234 123-456-7 2', function()
    return actions.profile_adapter('genmei', 'lead', 1234)
end)
expect_command('gs c ptgs action genmei middle 1234 123-456-7 2', function()
    return actions.profile_adapter('genmei', 'middle', 1234)
end)
expect_command('gs c ptgs action genmei setup 1234 123-456-7 2', function()
    return actions.profile_adapter('genmei', 'setup', 1234)
end)
expect_command('gs c ptgs action genmei close 1234 123-456-7 2', function()
    return actions.profile_adapter('genmei', 'close', '0000001234')
end)
expect_command('gs c ptgs action genmei proc 1234 123-456-7 2', function()
    return actions.profile_adapter('genmei', 'proc', 1234)
end)
expect_command('gs c ptgs action genmei burst 1234 123-456-7 2', function()
    return actions.profile_adapter('genmei', 'burst', 1234)
end)
expect_command('gs c ptgs action genmei cancel 1234 123-456-7 2', function()
    return actions.profile_adapter('genmei', 'cancel', 1234)
end)
expect_command(
    'gs c ptgs action genmei recover-songs 1234 123-456-7 2 tortoise-1234-1',
    function()
        return actions.profile_adapter(
            'genmei', 'recover-songs', 1234, 'tortoise-1234-1')
    end)
expect_command(
    'gs c ptgs action genmei strike-add 1234 123-456-7 2 wave-1 5003',
    function()
        return actions.profile_adapter(
            'genmei', 'strike-add', 1234, 'wave-1', 5003)
    end)
expect_command(
    'gs c ptgs action genmei silence-add 1234 123-456-7 2 - 4294967295',
    function()
        return actions.profile_adapter(
            'genmei', 'silence-add', 1234, nil, 4294967295)
    end)
expect_command('gs c ptgs action genmei probe 123-456-7 2 1', function()
    return actions.profile_adapter_probe('genmei', '123-456-7', 2, 1)
end)
for _, action in ipairs{'setup','lead','middle','close','dispel','proc','burst','cancel'} do
    expect_rejected(function()
        return actions.profile_adapter('genmei', action,
            '1; input /attack on')
    end)
end
expect_rejected(function()
    return actions.profile_adapter('genmei', 'cancel')
end)
expect_rejected(function()
    return actions.profile_adapter_probe('genmei', 'bad;nonce', 0, 1)
end)
expect_rejected(function()
    return actions.profile_adapter('genmei;input', 'lead', 1)
end)
expect_rejected(function()
    return actions.profile_adapter(
        'genmei', 'recover-songs', 1, 'bad;token')
end)
for _, invalid in ipairs({
    0, -1, 1.5, 4294967296, math.huge,
    '', '-1', '+1', '1.0', '1e3', '4294967296', '1;pc on', {}, false,
}) do
    expect_rejected(function()
        return actions.profile_adapter(
            'genmei', 'strike-add', 1, 'wave-1', invalid)
    end)
end
expect_rejected(function()
    return actions.profile_adapter(
        'genmei', 'strike-add', 1, 'wave-1', 0 / 0)
end)
for _, invalid in ipairs({
    0, -1, 1.5, 4294967296, math.huge,
    '', '-1', '+1', '1.0', '1e3', '4294967296', '1;pc on', {}, false,
}) do
    expect_rejected(function()
        return actions.controller('rdm', 'silence', invalid)
    end)
end
expect_rejected(function()
    return actions.controller('rdm', 'silence', 0 / 0)
end)
expect_rejected(function()
    return actions.controller('rdm', 'silence')
end)
expect_rejected(function()
    return actions.controller('rdm', 'silence', 1, 2)
end)
expect_rejected(function()
    return actions.controller('rdm', 'anything', 5003)
end)

assert(actions.equip == nil and actions.command == nil and actions.issue == nil)
assert(client.equip == nil and client.command == nil and client.issue == nil)

print('PartyTactics action API tests passed')
