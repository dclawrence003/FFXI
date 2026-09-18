local BASE = 'addons/PartyTactics/'

local function module(path)
    local loader, load_error = loadfile(BASE..path)
    assert(loader, load_error)
    return loader()
end

local util = module('lib/util.lua')
local fingerprint = module('lib/fingerprint.lua')
local identity_extensions = module('lib/identity_extensions.lua')
local base = module('data/profile_registry.lua')

local expected_ids = {
    'locus-dire-bats-tomb',
    'limbus-119-stationary',
    'ambuscade-2026-08-v1-breadwinner',
    'dynamis-divergence-wave1-route-corsair',
    'dynamis-divergence-wave1-boss-magic',
    'escha-ruaun-kammavaca',
    'escha-ruaun-genbu-genmei',
}

local frozen_snapshot = fingerprint.canonical(base)

local function assert_frozen_prefix(result)
    assert(fingerprint.canonical(base) == frozen_snapshot,
        'extension loading mutated the frozen base registry')
    assert(result.schema == base.schema)
    assert(#result.reserved_commands == #base.reserved_commands)
    for index, command in ipairs(base.reserved_commands) do
        assert(result.reserved_commands[index] == command,
            'public command changed at index '..index)
    end
    assert(#base.identities == #expected_ids)
    for ordinal, expected_id in ipairs(expected_ids) do
        local established = assert(result.identities[ordinal])
        assert(established == base.identities[ordinal],
            'established identity table was replaced at ordinal '..ordinal)
        assert(established.ordinal == ordinal)
        assert(established.id == expected_id,
            'established public identity changed at ordinal '..ordinal)
    end
end

local function fake_files(records, order)
    local function basename(path)
        return tostring(path):match('([^/\\]+)$')
    end
    local function get_dir(_)
        local result = {}
        for index, name in ipairs(order) do result[index] = name end
        return result
    end
    local function file_exists(path)
        local record = records[basename(path)]
        return record ~= nil and not record.missing
    end
    local function load_file(path)
        local record = assert(records[basename(path)])
        if record.load_error then return nil, record.load_error end
        if record.runtime_error then
            return function() error(record.runtime_error) end
        end
        return function() return record.identity end
    end
    return get_dir, file_exists, load_file
end

local function has_error(errors, fragment)
    for _, message in ipairs(errors or {}) do
        if tostring(message):find(fragment, 1, true) then return true end
    end
    return false
end

-- Directory enumeration order is irrelevant. Valid isolated identities are
-- appended strictly by ordinal, without changing an established identity or
-- public command.
do
    local records = {
        ['alpha-nine.lua']={identity={
            ordinal=9, id='alpha-nine', policy_id='pt-alpha-nine',
            aliases={'alpha9'},
        }},
        ['zulu-eight.lua']={identity={
            ordinal=8, id='zulu-eight', policy_id='pt-zulu-eight',
            aliases={'zulu8'},
        }},
        ['missing.lua']={missing=true},
    }
    local get_dir, file_exists, load_file = fake_files(records, {
        'alpha-nine.lua', 'README.md', 'missing.lua', 'zulu-eight.lua',
    })
    local result, errors = identity_extensions.extend(
        util, base, 'virtual/', get_dir, file_exists, load_file)
    assert(#errors == 0)
    assert_frozen_prefix(result)
    assert(#result.identities == 9)
    assert(result.identities[8].id == 'zulu-eight')
    assert(result.identities[9].id == 'alpha-nine')
end

-- A load error, execution error, invalid identity, ordinal collision, and
-- ordinal gap are each contained to their own sidecar. For duplicate ordinal
-- candidates the deterministic first candidate can own the next append slot;
-- every later duplicate is rejected and cannot replace it or any base owner.
do
    local records = {
        ['aaa-valid-eight.lua']={identity={
            ordinal=8, id='aaa-valid-eight', policy_id='pt-valid-eight',
            aliases={},
        }},
        ['bbb-duplicate.lua']={identity={
            ordinal=8, id='bbb-duplicate', policy_id='pt-duplicate-b',
            aliases={},
        }},
        ['ccc-duplicate.lua']={identity={
            ordinal=8, id='ccc-duplicate', policy_id='pt-duplicate-c',
            aliases={},
        }},
        ['broken-load.lua']={load_error='synthetic syntax failure'},
        ['exploding.lua']={runtime_error='synthetic execution failure'},
        ['wrong-file.lua']={identity={
            ordinal=9, id='different-id', policy_id='pt-wrong-file',
            aliases={},
        }},
        ['bad-alias.lua']={identity={
            ordinal=9, id='bad-alias', policy_id='pt-bad-alias',
            aliases={'repeat','repeat'},
        }},
        ['gap-ten.lua']={identity={
            ordinal=10, id='gap-ten', policy_id='pt-gap-ten', aliases={},
        }},
        ['phantom.lua']={missing=true},
    }
    local get_dir, file_exists, load_file = fake_files(records, {
        'gap-ten.lua', 'ccc-duplicate.lua', 'wrong-file.lua',
        'broken-load.lua', 'aaa-valid-eight.lua', 'bad-alias.lua',
        'exploding.lua', 'bbb-duplicate.lua', 'UPPER.lua', 'phantom.lua',
    })
    local result, errors = identity_extensions.extend(
        util, base, 'virtual/', get_dir, file_exists, load_file)
    assert_frozen_prefix(result)
    assert(#result.identities == 8)
    assert(result.identities[8].id == 'aaa-valid-eight')
    assert(has_error(errors, 'broken-load: synthetic syntax failure'))
    assert(has_error(errors, 'exploding: invalid isolated profile identity.'))
    assert(has_error(errors, 'wrong-file: invalid isolated profile identity.'))
    assert(has_error(errors, 'bad-alias: invalid isolated profile identity.'))
    assert(has_error(errors, 'bbb-duplicate: identity ordinal 8'))
    assert(has_error(errors, 'ccc-duplicate: identity ordinal 8'))
    assert(has_error(errors, 'gap-ten: identity ordinal 10'))
end

-- An invalid next ordinal does not let a later sidecar jump over the missing
-- slot. Both remain quarantined and the established registry is still usable.
do
    local records = {
        ['invalid-eight.lua']={identity={
            ordinal=8, id='invalid-eight', policy_id='INVALID', aliases={},
        }},
        ['valid-nine.lua']={identity={
            ordinal=9, id='valid-nine', policy_id='pt-valid-nine', aliases={},
        }},
    }
    local get_dir, file_exists, load_file = fake_files(records, {
        'valid-nine.lua', 'invalid-eight.lua',
    })
    local result, errors = identity_extensions.extend(
        util, base, 'virtual/', get_dir, file_exists, load_file)
    assert_frozen_prefix(result)
    assert(#result.identities == #base.identities)
    assert(has_error(errors, 'invalid-eight: invalid isolated profile identity.'))
    assert(has_error(errors, 'valid-nine: identity ordinal 9'))
end

print('PartyTactics isolated identity tests passed.')
