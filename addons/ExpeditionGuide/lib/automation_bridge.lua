-- Narrow route-action bridge. Content can select only an allowlisted Sortie
-- Superwarp operation; raw commands, destinations, delays, and recipients are
-- never accepted from route files.

local Bridge={}
Bridge.__index=Bridge

local COMMANDS={
    device_a='sw so p a',
    device_b='sw so p b',
    device_c='sw so p c',
    port='sw so p port',
}

local DEFAULT_RETRY_SECONDS=12

function Bridge.new(dispatch,options)
    options=options or {}
    return setmetatable({dispatch=dispatch,
        enabled=options.enabled~=false,
        retry_seconds=math.max(3,
            tonumber(options.retry_seconds) or DEFAULT_RETRY_SECONDS),
        emitted={}},Bridge)
end

function Bridge:set_enabled(value) self.enabled=value==true end
function Bridge:reset() self.emitted={} end

function Bridge:describe(action)
    if not action then return nil end
    local command=type(action)=='table' and COMMANDS[action.operation] or nil
    return command and ('AUTO //%s'):format(command)
        or 'INVALID ROUTE ACTION'
end

function Bridge:reconcile(action,token,context)
    context=context or {}
    if not action then return false,'no route action' end
    if type(action)~='table' or action.kind~='sortie_superwarp'
        or type(token)~='string' or #token<1 or #token>160
        or token:match('^[A-Za-z0-9:_-]+$')==nil
    then return false,'invalid route action' end
    local command=COMMANDS[action.operation]
    if not command then return false,'operation is not allowlisted' end
    if not self.enabled then return false,'route actions are disabled' end
    if context.is_leader~=true then return false,'leader only' end
    if context.in_allowed_zone~=true then return false,'wrong zone' end
    if context.route_active~=true then return false,'route is not active' end
    -- Do not ask Superwarp to search for an object that is not actually
    -- available yet. The route remains active and checks again every frame.
    if context.source_ready~=true then return false,'source is not in range' end
    if type(self.dispatch)~='function' then return false,'no dispatcher' end
    local now=tonumber(context.now) or os.clock()
    local previous=self.emitted[token]
    if previous and now-(tonumber(previous.at) or now)<self.retry_seconds then
        return false,'waiting before retry'
    end
    self.emitted[token]={at=now,attempts=previous
        and ((tonumber(previous.attempts) or 0)+1) or 1}
    self.dispatch(command)
    return true,'//'..command,self.emitted[token].attempts
end

return Bridge
