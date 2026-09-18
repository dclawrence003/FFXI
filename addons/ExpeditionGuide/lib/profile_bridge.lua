-- One-way, allowlisted PartyTactics lifecycle bridge. Route content names only
-- catalogued profile keys and a boolean arm state; it can never provide a raw
-- command. A desired state is emitted once, so Alt-P/manual improvisation is
-- never fought by a background re-arm loop.

local Bridge={}
Bridge.__index=Bridge

function Bridge.new(catalog,dispatch,options)
    return setmetatable({
        catalog=catalog or {},dispatch=dispatch,
        enabled=options and options.enabled==true or false,
        pending=nil,current_profile=nil,current_armed=false,
    },Bridge)
end

function Bridge:set_enabled(value) self.enabled=value==true end

local function validated_profile(bridge,profile_key)
    local profile=bridge.catalog[profile_key]
    if not profile then return nil,'profile is not allowlisted' end
    if profile.available~=true then return nil,'profile is not installed' end
    local canonical_id=profile.canonical_id
    if type(canonical_id)~='string'
        or canonical_id:match('^[a-z0-9][a-z0-9_-]*$')==nil
    then return nil,'invalid canonical profile id' end
    if type(bridge.dispatch)~='function' then return nil,'no dispatcher' end
    return profile
end

local function use_command(canonical_id,armed)
    return 'lua i PartyTactics use '..canonical_id
        ..(armed==true and '' or ' inert')
end

local function dispatch_profile(bridge,canonical_id,armed)
    bridge.dispatch(use_command(canonical_id,armed))
end

function Bridge:describe(profile_key,armed)
    if not profile_key then
        return 'none','no PartyTactics profile on this travel step'
    end
    local profile=self.catalog[profile_key]
    if not profile then
        return 'none','unknown profile key '..tostring(profile_key)
    end
    if profile.available~=true then
        return 'planned','profile not installed: '..tostring(profile.canonical_id)
    end
    local command='//pt use '..tostring(profile.canonical_id)
        ..(armed==true and '' or ' inert')
    if not self.enabled then return 'manual',command end
    return 'auto',command
end

function Bridge:reset()
    self.pending=nil
    self.current_profile=nil
    self.current_armed=false
end

function Bridge:clear_pending() self.pending=nil end

-- Recovery command for //exg profile. Unlike the old UI, its result always
-- exposes the actual canonical PartyTactics operation.
function Bridge:request_operator(profile_key,armed)
    local profile,reason=validated_profile(self,profile_key)
    if not profile then return false,reason end
    dispatch_profile(self,profile.canonical_id,armed==true)
    self.current_profile=profile.canonical_id
    self.current_armed=armed==true
    return true,use_command(profile.canonical_id,armed==true)
end

-- Automatic reconciliation has structural gates only. It never waits for an
-- idle status, preflight, ACK, sensor quorum, buff, or quiet encounter.
function Bridge:reconcile(profile_key,armed,context)
    context=context or {}
    if not self.enabled then return false,'automatic bridge is disabled' end
    if context.is_leader~=true then return false,'leader only' end
    if context.in_allowed_zone~=true then return false,'wrong zone' end
    if context.route_active~=true then return false,'route is not active' end

    if not profile_key then
        if self.current_profile and self.current_armed then
            self.dispatch('lua i PartyTactics disarm')
            self.current_profile=nil
            self.current_armed=false
            return true,'//pt disarm'
        end
        self.current_profile=nil
        self.current_armed=false
        return false,'no profile desired'
    end

    local profile,reason=validated_profile(self,profile_key)
    if not profile then return false,reason end
    local desired_armed=armed==true
    if self.current_profile==profile.canonical_id
        and self.current_armed==desired_armed
    then return false,'desired state already emitted' end

    dispatch_profile(self,profile.canonical_id,desired_armed)
    self.current_profile=profile.canonical_id
    self.current_armed=desired_armed
    return true,'//pt use '..profile.canonical_id
        ..(desired_armed and '' or ' inert')
end

-- Backward-compatible one-shot request. New route lifecycle code uses
-- reconcile and deliberately omits the transient readiness gates that made
-- the guide a blocker.
function Bridge:request(profile_key,context,now)
    return self:reconcile(profile_key,false,{
        is_leader=context and context.is_leader,
        in_allowed_zone=context and context.in_allowed_zone,
        route_active=true,
    })
end

function Bridge:emergency_stop()
    if type(self.dispatch)~='function' then return false,'no dispatcher' end
    self:reset()
    self.dispatch('lua i PartyTactics off')
    return true
end

return Bridge
