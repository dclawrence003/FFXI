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
        add_to_chat(122,
            'PartyStart GEO: redundant native Haste/Refresh/Aurorastorm/'
            ..'Reraise maintenance suppressed; colure automation unchanged.')
    elseif requested == 'restore' or requested == 'off' then
        if pstart_geo_saved_auto ~= nil then
            buff_spell_lists.Auto = pstart_geo_saved_auto
            pstart_geo_saved_auto = nil
        end
        add_to_chat(122, 'PartyStart GEO: native Auto self-buff list restored.')
    elseif requested == 'status' or not requested then
        add_to_chat(122, ('PartyStart GEO lean mode: %s')
            :format(pstart_geo_saved_auto and 'On' or 'Off'))
    else
        add_to_chat(123,
            'PartyStart GEO usage: gs c pstartgeo <lean|restore|status>')
    end
end
