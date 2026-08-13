-- PartyStart GEO controller for Selindrile-style GearSwap files.
-- Integration target: https://github.com/Selindrile/GearSwap
--
-- GEO's native Auto mode maintains Haste, Refresh, Aurorastorm, and Reraise
-- in addition to colures. PartyStart's RDM already supplies stronger Haste II
-- and Refresh III, so the sustained profile replaces that self-buff list with
-- an empty one while leaving native Indi/Geo/Entrust logic untouched.
-- Load at the end of a participating character's GEO gear file:
--     include('Common/PartyStart_GEO.lua')

local pstart_geo_saved_auto = nil
local pstart_geo_active = false

local function pstart_geo_set_autobuff(value)
    if state and state.AutoBuffMode then
        state.AutoBuffMode:set(value)
    end
end

-- Character/shared GEO setup files historically enabled AutoBuff one second
-- after every GearSwap load. Force an inert baseline after all setup has
-- completed, unless PartyStart has already activated a profile during that
-- window. This makes the delayed guard unable to undo a legitimate startup.
send_command('wait 2; gs c pstartgeo bootidle')

local pstart_geo_original_self_command = user_job_self_command
function user_job_self_command(commandArgs, eventArgs)
    local command = commandArgs[1] and commandArgs[1]:lower() or nil
    if command ~= 'pstartgeo' then
        if pstart_geo_original_self_command then
            return pstart_geo_original_self_command(commandArgs, eventArgs)
        end
        return
    end

    eventArgs.handled = true
    local requested = commandArgs[2] and commandArgs[2]:lower() or nil
    if requested == 'lean' then
        if pstart_geo_saved_auto == nil then
            pstart_geo_saved_auto = buff_spell_lists.Auto
        end
        buff_spell_lists.Auto = {}
        pstart_geo_active = true
        add_to_chat(122,
            'PartyStart GEO: redundant native Haste/Refresh/Aurorastorm/'
            ..'Reraise maintenance suppressed; colure automation unchanged.')
    elseif requested == 'bootidle' then
        if not pstart_geo_active then
            pstart_geo_set_autobuff('Off')
            add_to_chat(122, 'PartyStart GEO: idle until a profile is started.')
        end
    elseif requested == 'idle' or requested == 'off' then
        if pstart_geo_saved_auto ~= nil then
            buff_spell_lists.Auto = pstart_geo_saved_auto
            pstart_geo_saved_auto = nil
        end
        pstart_geo_active = false
        pstart_geo_set_autobuff('Off')
        add_to_chat(122,
            'PartyStart GEO: idle; colure and native buff automation are Off.')
    elseif requested == 'restore' then
        if pstart_geo_saved_auto ~= nil then
            buff_spell_lists.Auto = pstart_geo_saved_auto
            pstart_geo_saved_auto = nil
        end
        pstart_geo_active = true
        add_to_chat(122, 'PartyStart GEO: native Auto self-buff list restored.')
    elseif requested == 'status' or not requested then
        add_to_chat(122, ('PartyStart GEO: %s; lean mode: %s; AutoBuff: %s')
            :format(
                pstart_geo_active and 'Active' or 'Idle',
                pstart_geo_saved_auto and 'On' or 'Off',
                state and state.AutoBuffMode and state.AutoBuffMode.value
                    or 'Unavailable'))
    else
        add_to_chat(123,
            'PartyStart GEO usage: gs c pstartgeo '
            ..'<lean|restore|idle|off|status>')
    end
end
