local BASE = 'addons/PartyTactics/'

local function module(path)
    local loader, load_error = loadfile(BASE..path)
    assert(loader, load_error)
    return loader()
end

local util = module('lib/util.lua')
local supplemental_aliases = module('lib/supplemental_aliases.lua')
local base_registry = module('data/profile_registry.lua')

local function copy_array(values)
    local result = {}
    for index, value in ipairs(values or {}) do result[index] = value end
    return result
end

local registry = {
    schema=base_registry.schema,
    reserved_commands=copy_array(base_registry.reserved_commands),
    identities=copy_array(base_registry.identities),
}
for _, path in ipairs({
    'data/profile_identities/ambuscade-2026-09-v1-qutrub-bigwig.lua',
    'data/profile_identities/ambuscade-2026-09-v2-hydra-alluttu.lua',
    'data/profile_identities/ambuscade-2026-09-v1-qutrub-bigwig-no-cait.lua',
}) do
    registry.identities[#registry.identities + 1] = module(path)
end

local AUGUST = 'ambuscade-2026-08-v1-breadwinner'
local QUTRUB = 'ambuscade-2026-09-v1-qutrub-bigwig'
local QUTRUB_NO_CAIT = 'ambuscade-2026-09-v1-qutrub-bigwig-no-cait'
local HYDRA = 'ambuscade-2026-09-v2-hydra-alluttu'
local profiles = {
    [AUGUST]={id=AUGUST},
    [QUTRUB]={id=QUTRUB},
    [QUTRUB_NO_CAIT]={id=QUTRUB_NO_CAIT},
    [HYDRA]={id=HYDRA},
}
local established = {
    [AUGUST]=AUGUST, ['v1']=AUGUST, breadwinner=AUGUST,
    [QUTRUB]=QUTRUB, qutrub=QUTRUB,
    [QUTRUB_NO_CAIT]=QUTRUB_NO_CAIT, ['qutrub-nocait']=QUTRUB_NO_CAIT,
    [HYDRA]=HYDRA, hydra=HYDRA,
    ['legacy-only']=AUGUST,
}

local function contains(errors, fragment)
    for _, message in ipairs(errors or {}) do
        if tostring(message):find(fragment, 1, true) then return true end
    end
    return false
end

-- The four reviewed sidecars load independently and add only the requested
-- encounter-qualified names. Historical aliases and the input map are intact.
do
    local names = {
        AUGUST..'.lua', QUTRUB..'.lua', QUTRUB_NO_CAIT..'.lua',
        HYDRA..'.lua', 'README.md',
    }
    local root = BASE..'data/supplemental_aliases/'
    local sidecars, discovery_errors = supplemental_aliases.discover(
        util, root, function() return names end,
        function(path) return path:sub(-4) == '.lua' end,
        loadfile)
    assert(#sidecars == 4 and #discovery_errors == 0)

    local result, apply_errors = supplemental_aliases.apply(
        util, sidecars, profiles, established, registry, {})
    assert(#apply_errors == 0)
    assert(result['v1-breadwinner'] == AUGUST)
    assert(result['v1-qutrub'] == QUTRUB)
    assert(result['v1-qutrub-nocait'] == QUTRUB_NO_CAIT)
    assert(result['v2-hydra'] == HYDRA)
    assert(result.v1 == AUGUST and result.breadwinner == AUGUST)
    assert(result.qutrub == QUTRUB and result.hydra == HYDRA)
    assert(established['v1-breadwinner'] == nil,
        'loader mutated the established alias table')
    assert(result ~= established, 'loader must return an isolated alias map')
end

-- Sidecar discovery is deterministic. A syntax failure and invalid sidecar
-- quarantine only their own files; valid siblings remain available.
do
    local root = 'virtual/'
    local records = {
        [AUGUST..'.lua']={sidecar={
            schema=1, target=AUGUST, aliases={'valid-august'},
        }},
        [QUTRUB..'.lua']={load_error='synthetic syntax failure'},
        [QUTRUB_NO_CAIT..'.lua']={runtime_error='synthetic execution failure'},
        [HYDRA..'.lua']={sidecar={
            schema=1, target='wrong-target', aliases={'invalid-hydra'},
        }},
    }
    local function discover(order)
        return supplemental_aliases.discover(
            util, root, function() return order end,
            function(path)
                return records[path:match('([^/]+)$')] ~= nil
            end,
            function(path)
                local record = records[path:match('([^/]+)$')]
                if record.load_error then return nil, record.load_error end
                if record.runtime_error then
                    return function() error(record.runtime_error) end
                end
                return function() return record.sidecar end
            end)
    end
    local forward = {QUTRUB..'.lua', HYDRA..'.lua', AUGUST..'.lua',
        QUTRUB_NO_CAIT..'.lua'}
    local reverse = {QUTRUB_NO_CAIT..'.lua', AUGUST..'.lua', HYDRA..'.lua',
        QUTRUB..'.lua'}
    local sidecars, errors = discover(forward)
    local reverse_sidecars, reverse_errors = discover(reverse)
    assert(#sidecars == 1 and sidecars[1].target == AUGUST)
    assert(#reverse_sidecars == 1 and reverse_sidecars[1].target == AUGUST)
    assert(table.concat(errors, '|') == table.concat(reverse_errors, '|'))
    assert(contains(errors, 'synthetic syntax failure'))
    assert(contains(errors, QUTRUB_NO_CAIT
        ..': invalid isolated supplemental aliases'))
    assert(contains(errors, HYDRA..': invalid isolated supplemental aliases'))
end

-- Optional I/O callbacks are containment boundaries. A thrown directory read
-- disables only the overlay; per-file check/load failures leave valid siblings.
do
    local sidecars, errors = supplemental_aliases.discover(
        util, 'virtual/', function() error('synthetic directory failure') end,
        function() return true end, function() return function() end end)
    assert(#sidecars == 0 and #errors == 1)
    assert(contains(errors, 'synthetic directory failure'))

    local names = {AUGUST..'.lua', QUTRUB..'.lua', HYDRA..'.lua'}
    sidecars, errors = supplemental_aliases.discover(
        util, 'virtual/', function() return names end,
        function(path)
            if path:find(QUTRUB, 1, true) then
                error('synthetic file-check failure')
            end
            return true
        end,
        function(path)
            if path:find(HYDRA, 1, true) then
                error('synthetic loader failure')
            end
            return function()
                return {schema=1, target=AUGUST, aliases={'valid-sibling'}}
            end
        end)
    assert(#sidecars == 1 and sidecars[1].target == AUGUST)
    assert(contains(errors, 'synthetic file-check failure'))
    assert(contains(errors, 'synthetic loader failure'))
end

-- Commands, every immutable identity name, established aliases, and every
-- loaded profile's direct manual actions retain priority. Alias chains,
-- duplicates, and quarantined targets fail closed; an unrelated valid name
-- remains usable.
do
    local available = {}
    for id, profile in pairs(profiles) do available[id] = profile end
    available[HYDRA] = nil
    local sidecars = {
        {schema=1, target=AUGUST, aliases={
            'status', QUTRUB, 'bigwig', 'legacy-only', 'fight-action',
            'still-valid', 'duplicate-name',
        }},
        {schema=1, target=QUTRUB, aliases={'duplicate-name'}},
        {schema=1, target='qutrub', aliases={'alias-chain'}},
        {schema=1, target=HYDRA, aliases={'missing-target'}},
    }
    local result, errors = supplemental_aliases.apply(
        util, sidecars, available, established, registry,
        {['fight-action']=true})
    assert(result.status == nil and result[QUTRUB] == QUTRUB)
    assert(result.qutrub == QUTRUB and result['legacy-only'] == AUGUST)
    assert(result['fight-action'] == nil and result['alias-chain'] == nil)
    assert(result['missing-target'] == nil and result['duplicate-name'] == nil)
    assert(result['still-valid'] == AUGUST)
    assert(contains(errors, 'conflicts with PartyTactics command'))
    assert(contains(errors, 'conflicts with canonical profile '..QUTRUB))
    assert(contains(errors, 'conflicts with profile alias for '..QUTRUB))
    assert(contains(errors, 'conflicts with an established profile alias'))
    assert(contains(errors, 'conflicts with a profile manual action'))
    assert(contains(errors, 'target qutrub is not a canonical profile id'))
    assert(contains(errors, 'target '..HYDRA..' is unavailable or quarantined'))
    assert(contains(errors, 'shortcut duplicate-name is claimed by'))
end

-- Invalid collections and identity registries disable only the overlay.
do
    local result, errors = supplemental_aliases.apply(
        util, {[2]={schema=1, target=AUGUST, aliases={'array-gap'}}},
        profiles, established, registry, {})
    assert(result.v1 == AUGUST and result['array-gap'] == nil)
    assert(#errors == 1 and contains(errors, 'sidecar set is invalid'))

    local invalid_registry = {
        schema=1,
        reserved_commands={'status'},
        identities={{
            ordinal=2, id=AUGUST, policy_id='pt-ambu2608v1', aliases={'v1'},
        }},
    }
    result, errors = supplemental_aliases.apply(
        util, {{schema=1, target=AUGUST, aliases={'would-be-valid'}}},
        profiles, established, invalid_registry, {})
    assert(result.v1 == AUGUST and result['would-be-valid'] == nil)
    assert(#errors == 1 and contains(errors, 'identity namespace is invalid'))

    local throwing_profiles = setmetatable({}, {
        __index=function() error('synthetic profile lookup failure') end,
    })
    result, errors = supplemental_aliases.apply(
        util, {{schema=1, target=AUGUST, aliases={'apply-failure'}}},
        throwing_profiles, established, registry, {})
    assert(result.v1 == AUGUST and result['apply-failure'] == nil)
    assert(#errors == 1 and contains(errors, 'synthetic profile lookup failure'))

    local _, discovery_errors = supplemental_aliases.discover(
        util, 'empty/', function() return {} end,
        function() return false end, loadfile)
    assert(#discovery_errors == 1)
    assert(contains(discovery_errors, 'no supplemental alias sidecars found'))
end

print('PartyTactics supplemental alias tests passed.')
