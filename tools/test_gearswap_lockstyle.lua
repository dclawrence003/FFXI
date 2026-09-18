-- Offline regression test: executes the installed profiles/common setup files
-- and Selendrile's real lockstyle/subjob handlers with a simulated clock.
local gs_root = assert(os.getenv('GEARSWAP_TEST_ROOT'), 'Supply GEARSWAP_TEST_ROOT'):gsub('\\', '/')
local data_root = gs_root..'/data/'
local libs_root = gs_root..'/libs/'

local function read(path)
    local file = assert(io.open(path, 'r'))
    local text = file:read('*a')
    file:close()
    return text
end

local function function_block(path, first, next_function)
    local source = read(path)
    local start = assert(source:find(first, 1, true))
    local finish = assert(source:find(next_function, start + #first, true))
    return source:sub(start, finish - 1)
end

-- Fengari has loadfile but not io.open; the PowerShell runner supplies these
-- exact source blocks through environment variables for that runtime.
local check_source = os.getenv('GEARSWAP_TEST_LOCKSTYLE_SOURCE') or function_block(libs_root..'Sel-Utility.lua',
    'function check_lockstyle()', 'function check_food()')
local subjob_source = os.getenv('GEARSWAP_TEST_SUBJOB_SOURCE') or function_block(libs_root..'Sel-Include.lua',
    'function sub_job_change(newSubjob, oldSubjob)', 'function status_change(')

-- Character, main job, macro book, macro page, owned style, template style.
local profiles = {
    {'Tackleberry', 'PLD', 1, 1, 1, 7},
    {'Kickpuncher', 'DNC', 1, 1, 1, 19},
    {'Barneystinson', 'BRD', 1, 1, 1, 10},
    {'Smalls', 'RDM', 1, 1, 1, 5},
    {'Achoo', 'GEO', 1, 1, 1, 21},
    {'Dolomedes', 'COR', 15, 2, 9, 17},
    {'Dolomedes', 'BLU', 4, 10, 7, 16},
}
local subjobs = {'WAR','MNK','WHM','BLM','RDM','THF','PLD','DRK','BST','BRD',
    'RNG','SAM','NIN','DRG','SMN','BLU','COR','PUP','DNC','SCH','GEO','RUN','NON'}

local function mode(value)
    local result = {value=type(value) == 'table' and value[1] or value}
    function result:options(...) self.values = {...} end
    function result:set(new_value) self.value = new_value end
    return result
end

local function runtime(profile, subjob, managed)
    local now, commands, inputs, macros = 0, {}, {}, {}
    local env = setmetatable({
        state=setmetatable({AutoLockstyle=mode(true)}, {__index=function(t, key)
            local value = mode('None')
            rawset(t, key, value)
            return value
        end}),
        player={name=profile[1], main_job=profile[2], sub_job=subjob},
        gear={}, info={}, options={}, autows_list={},
        M=mode, enable=function() end, update_defense_mode=function() end,
        set_dual_wield=function() end, handle_update=function() end,
        os={clock=function() return now end},
        send_command=function(command) commands[#commands+1] = command end,
        set_macro_page=function(page, book)
            macros[#macros+1] = {page=page, book=book}
        end,
        windower={chat={input=function(command)
            inputs[#inputs+1] = {time=now, command=command}
        end}},
        -- Simulate a preceding character-global selector; the job must override it.
        select_default_macro_book=function() end,
        style_lock=true, style_delay=15,
    }, {__index=_G})
    function env.include(path)
        if path:match('_UserSetup_Common%.lua$') then
            assert(loadfile(data_root..path, 't', env))()
        elseif path:find('PartyStart', 1, true) or path:find('PartyOpsTrace', 1, true) then
            -- Unrelated live party/event integrations must not run in an offline test.
            return
        else
            error('Unexpected setup include: '..path)
        end
    end
    assert(load(check_source, '@installed-check_lockstyle', 't', env))()
    assert(load(subjob_source, '@installed-sub_job_change', 't', env))()
    if managed then
        local path = data_root..profile[1]..'/'..profile[1]..'_'..profile[2]..'_Gear.lua'
        assert(loadfile(path, 't', env))()
        env.user_setup()
    else
        env.include('Common/'..profile[2]..'_UserSetup_Common.lua')
    end
    return env, function(time) now = time end, commands, inputs, macros
end

local function check_setup(profile, env, commands, inputs, macros)
    assert(env.style_lock and env.style_delay == 30, 'startup must defer to 30 seconds')
    assert(#inputs == 0, 'setup must not send an immediate style request')
    for _, command in ipairs(commands) do
        assert(not command:lower():find('/lockstyle', 1, true),
            'managed setup queued a competing style command: '..command)
    end
    assert(#macros > 0, 'macro book/page was not selected')
    for _, macro in ipairs(macros) do
        assert(macro.book == profile[3] and macro.page == profile[4], 'wrong macro book/page')
    end
end

for _, profile in ipairs(profiles) do
    -- Exercise all main/subjob combinations without relying on a particular subjob.
    for _, subjob in ipairs(subjobs) do
        local env, _, commands, inputs, macros = runtime(profile, subjob, true)
        check_setup(profile, env, commands, inputs, macros)
    end

    local env, clock, commands, inputs, macros = runtime(profile, 'WAR', true)
    local function tick(time) clock(time); env.check_lockstyle() end
    for _, time in ipairs({5,10,15,16,29,30}) do tick(time) end
    assert(#inputs == 0, 'lockstyle fired before the startup deadline')
    tick(30.1)
    tick(30.2)
    assert(#inputs == 1 and inputs[1].command == '/lockstyleset '..profile[5],
        'startup must send exactly one request for the configured style')

    -- Sel-Include's weapon-mode changes set style_lock; repeated requests coalesce.
    env.style_lock = true
    tick(31)
    env.style_lock = true
    tick(40)
    assert(#inputs == 1, 'weapon changes bypassed the cooldown')
    tick(43.2)
    tick(43.3)
    assert(#inputs == 2 and inputs[2].time - inputs[1].time >= 13,
        'weapon changes must produce one cooldown-gated request')

    -- Execute the real subjob handler twice: no queued old style survives the reset.
    clock(44)
    env.player.sub_job = 'RDM'
    env.sub_job_change('RDM', 'WAR')
    assert(env.style_delay == 74)
    clock(50)
    env.player.sub_job = 'NIN'
    env.sub_job_change('NIN', 'RDM')
    assert(env.style_delay == 80)
    tick(74.1)
    assert(#inputs == 2, 'an obsolete subjob deadline still fired')
    tick(80.1)
    tick(80.2)
    assert(#inputs == 3, 'subjob changes must coalesce into one style request')
    for _, input in ipairs(inputs) do
        assert(input.command == '/lockstyleset '..profile[5], 'wrong appearance selected')
    end
    for _, command in ipairs(commands) do
        assert(not command:lower():find('/lockstyle', 1, true), 'queued duplicate after subjob change')
    end
    for _, macro in ipairs(macros) do
        assert(macro.book == profile[3] and macro.page == profile[4], 'subjob changed the macros')
    end

    env.style_lock = true
    env.state.AutoLockstyle.value = false
    tick(100)
    assert(#inputs == 3, 'the manual AutoLockstyle toggle was ignored')

    -- Other characters using these shared templates retain their previous defaults.
    local _, _, fallback_commands = runtime(profile, 'WAR', false)
    local fallback_count, dressup = 0, false
    for _, command in ipairs(fallback_commands) do
        if command:find('/lockstyleset', 1, true) then
            fallback_count = fallback_count + 1
            assert(command:match('/lockstyleset (%d+)') == tostring(profile[6]))
        end
        if command == (profile[2] == 'BRD' and 'wait 13; lua load dressup'
            or 'wait 18; lua load dressup') then dressup = true end
    end
    assert(fallback_count == 1, 'unmanaged template fallback changed')
    if profile[2] == 'BRD' or profile[2] == 'RDM' then
        assert(dressup, 'DressUp startup was lost')
    end
    print('PASS '..profile[1]..'/'..profile[2]..': 23 subjobs, single startup request, cooldown, subjob coalescing, template fallback')
end
print('All lockstyle regression tests passed.')
