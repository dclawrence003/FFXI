-- Shared real host/helper probe boundary. Full job ticks are outside this fixture.
-- Designed and directed by Don Lawrence; developed using OpenAI Codex.
return function(lab, on_reply)
    local unpack_values=table.unpack or unpack
    local function words(s)
        local t={}; for w in s:gmatch('%S+') do t[#t+1]=w end; return t
    end
    local function load_into(path,env)
        local chunk,err
        if setfenv then chunk,err=loadfile(path); if chunk then setfenv(chunk,env) end
        else chunk,err=loadfile(path,'t',env) end
        assert(chunk,err)()
    end
    for _,c in ipairs(lab.clients) do
        c.host_probe_enabled=false; c.helper_probe_enabled=false
        local env=setmetatable({}, {__index=_G}); env._G=env
        c.helper_startup_commands={}
        env.send_command=function(s) c.helper_startup_commands[#c.helper_startup_commands+1]=s end
        env.include=function() error('Unexpected adapter load in probe fixture') end
        env.require=function(name)
            assert(name=='packets','Unexpected helper dependency: '..name)
            return {new=function() error('Unexpected packet construction during readiness') end}
        end
        env.windower={raw_register_event=function() end,add_to_chat=function() end,
            send_command=function(s)
                assert(s:match('^pt __gearswap_host_ready ') or s:match('^pt __legacy_helper_ready '),
                    'Unexpected readiness output: '..s)
                if on_reply and on_reply(c,s)==false then return end
                local t=words(s); table.remove(t,1)
                lab.fire(c,'addon command',unpack_values(t))
            end}
        if c.player.main_job~='COR' then
            load_into('addons/PartyStart/gearswap/PartyStart_'..c.player.main_job..'.lua',env)
        end
        load_into('addons/PartyTactics/gearswap/PartyTactics_Host.lua',env)
        local previous=c.command_sink
        c.command_sink=function(s)
            if previous then previous(s) end
            for part in s:gmatch('[^;]+') do
                part=part:match('^%s*(.-)%s*$')
                if part:match('^gs c ptgs probe ') or part:match('^gs c pstart%a+ probe ') then
                    local t=words(part); table.remove(t,1); table.remove(t,1)
                    local event={}; env.user_job_self_command(t,event)
                    assert(event.handled,'Real host/helper failed to consume '..part)
                end
            end
        end
    end
end
