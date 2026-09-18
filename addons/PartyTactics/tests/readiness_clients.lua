-- Shared real host/helper probe boundary. Full job ticks are outside this fixture.
-- Designed and directed by Don Lawrence; developed using OpenAI Codex.
return function(lab, on_reply, controllers)
    local unpack_values=table.unpack or unpack
    local function words(s)
        local t={}; for w in s:gmatch('%S+') do t[#t+1]=w end; return t
    end
    local function load_into(path,env)
        local chunk,err
        if setfenv then chunk,err=loadfile(path); if chunk then setfenv(chunk,env) end
        else chunk,err=loadfile(path,'t',env) end
        return assert(chunk,err)()
    end
    for _,c in ipairs(lab.clients) do
        c.host_probe_enabled=false; c.helper_probe_enabled=false
        if controllers then c.controller_probe_enabled=false end
        local env=setmetatable({}, {__index=_G}); env._G=env
        c.helper_startup_commands={}
        env.send_command=function(s) c.helper_startup_commands[#c.helper_startup_commands+1]=s end
        env.os={clock=lab.now}
        env.player=setmetatable({mp=1500,tp=1000}, {__index=function(_,key)
            if key=='status' then return c.player.status==1 and 'Engaged' or 'Idle' end
            return c.player[key]
        end})
        env.res=c.environment.require('resources')
        env.midaction=function() return false end
        env.silent_check_disable=function() return false end
        env.silent_can_use=function() return true end
        env.include=function(path)
            assert(controllers and path=='Common/PartyTactics/adapters/sortie-main-v1/1.2.0.lua',
                'Unexpected adapter load: '..tostring(path))
            return load_into('addons/PartyTactics/gearswap/adapters/sortie-main-v1/1.2.0.lua',env)
        end
        env.require=function(name)
            assert(name=='packets','Unexpected helper dependency: '..name)
            return {new=function() error('Unexpected packet construction during readiness') end}
        end
        c.adapter_inputs={}
        c.host_chats={}
        env.windower={raw_register_event=function() end,add_to_chat=function(_,s) c.host_chats[#c.host_chats+1]=s end,
            ffxi=setmetatable({get_mob_by_target=function(token)
                if token=='bt' then return c.battle end
                if token=='t' then return c.current_target end
                error('Unexpected target token: '..tostring(token))
            end,get_spell_recasts=function() return {[146]=0,[147]=0,[164]=0,[465]=0} end},
                {__index=c.environment.windower.ffxi}),
            chat={input=function(s) c.adapter_inputs[#c.adapter_inputs+1]=s end},
            send_command=function(s)
                if not s:match('^pt ') then
                    c.helper_startup_commands[#c.helper_startup_commands+1]=s; return
                end
                if on_reply and on_reply(c,s)==false then return end
                local t=words(s); table.remove(t,1)
                lab.fire(c,'addon command',unpack_values(t))
            end}
        if c.player.main_job~='COR' then
            load_into('addons/PartyStart/gearswap/PartyStart_'..c.player.main_job..'.lua',env)
        end
        c.real_host=load_into('addons/PartyTactics/gearswap/PartyTactics_Host.lua',env)
        c.host_tick=env.pre_tick
        local previous=c.command_sink
        c.command_sink=function(s)
            if previous then previous(s) end
            for part in s:gmatch('[^;]+') do
                part=part:match('^%s*(.-)%s*$')
                if part:match(controllers and '^gs c ptgs ' or '^gs c ptgs probe ')
                    or part:match('^gs c pstart%a+ probe ') then
                    local t=words(part); table.remove(t,1); table.remove(t,1)
                    local event={}; env.user_job_self_command(t,event)
                    assert(event.handled,'Real host/helper failed to consume '..part)
                end
            end
        end
    end
end
