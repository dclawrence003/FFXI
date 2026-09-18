-- Run from the repository root with stock Lua 5.1 or LuaJIT.
local json = dofile('addons/CombatRecorder/lib/json_encode.lua')
local storage = dofile('addons/CombatRecorder/lib/recorder.lua')
local passed = 0
local function test(name, fn)
    local ok, err = pcall(fn)
    assert(ok, name .. ': ' .. tostring(err)); passed = passed + 1
    print('PASS ' .. name)
end
local function fake(options)
    local state = {now = 1800000000, files = {}, removed = {}, writes = 0}
    local deps = {now = function() return state.now end, clock = function() return state.now / 100 end,
        encode = json.encode, exists = function(path) return state.files[path] ~= nil end,
        list = function(dir)
            local result = {}
            for path in pairs(state.files) do if path:sub(1, #dir) == dir then result[#result + 1] = path:sub(#dir + 1) end end
            return result
        end,
        remove = function(path) state.removed[#state.removed + 1] = path; state.files[path] = nil; return true end,
        open = function(path, mode)
            if state.fail_open then return nil, 'disk unavailable' end
            if mode == 'wb' then state.files[path] = '' end
            return {write = function(self, text)
                if state.fail_write then return nil, 'disk full' end
                state.files[path] = (state.files[path] or '') .. text; state.writes = state.writes + 1
                return self
            end, close = function() return not state.fail_close end}
        end}
    options = options or {}; options.character = 'Smalls'; options.directory = 'C:/capture/Smalls'
    return storage.new(options, deps), state, deps
end

test('JSON strings, empty arrays, finite numbers, cycles', function()
    assert(json.encode({a = 'x\n"\\', b = json.array(), c = 0/0}) == '{"a":"x\\u000a\\"\\\\","b":[],"c":null}')
    local value = {}; value.x = value
    assert(not pcall(json.encode, value))
    assert(json.encode(string.char(255)) == '"\\u00ff"')
end)
test('buffering and verifiable disk write', function()
    local r, s = fake()
    r:record('snapshot', {hp = 2000})
    assert(s.writes == 0 and r.last_write == 0)
    r:tick({recording = true}, true)
    assert(r.last_write == s.now and r.queued_bytes == 0)
    assert(s.files[r.directory .. 'health.json']:find('last_data_write'))
end)
test('death archive includes prehistory and aftermath', function()
    local r, s = fake()
    r:record('old', {}); s.now = s.now + 301
    r:record('before_death', {}); r:mark('party_death', {victim = 'Smalls'})
    r:record('death', {}); s.now = s.now + 60; r:record('aftermath', {})
    s.now = s.now + 61; r:record('outside', {}); r:close({})
    local content = s.files[r.directory .. r.last_incident]
    assert(content:find('before_death') and content:find('aftermath'))
    assert(not content:find('"kind":"old"') and not content:find('"kind":"outside"'))
end)
test('related deaths extend one archive, new incident after timeout', function()
    local r, s = fake()
    r:mark('party_death'); local first = r.last_incident
    s.now = s.now + 100; r:mark('party_death'); assert(r.last_incident == first)
    s.now = s.now + 121; r:mark('party_death'); assert(r.last_incident ~= first)
end)
test('disk outage is bounded and retries after backoff', function()
    local r, s = fake({queue_bytes = 1000, ring_bytes = 500})
    s.fail_open = true
    for i = 1, 40 do r:record('sample', {n = i}) end
    r:tick({}, true)
    assert(r.queued_bytes <= 1000 and r.ring_size <= 500 and r.dropped > 0 and r.last_write == 0)
    s.fail_open = false; r:tick({}, true); assert(r.last_write == 0)
    s.now = s.now + 30; r:tick({}, true); assert(r.last_write == s.now and not r.last_error)
end)
test('partial write failure is visible and not blindly duplicated', function()
    local r, s = fake()
    r:record('event', {}); s.fail_close = true; r:flush()
    assert(r.dropped == 1 and r.write_errors == 1 and r.last_write == 0 and r.queued_bytes == 0)
end)
test('rotation prunes only own exact filenames', function()
    local r, s = fake({segment_bytes = 420, segments = 2})
    s.files[r.directory .. '../untouchable.txt'] = 'keep'
    s.files[r.directory .. 'user-notes.jsonl'] = 'keep'
    for i = 1, 20 do r:record('snapshot', {n = i}); r:flush() end
    r:prune()
    local count = 0
    for path in pairs(s.files) do if path:find('/combat%-') then count = count + 1 end end
    assert(count <= 2 and #s.removed > 0)
    assert(s.files[r.directory .. '../untouchable.txt'] and s.files[r.directory .. 'user-notes.jsonl'])
    for _, path in ipairs(s.removed) do assert(path:match('^C:/capture/Smalls/combat%-%d+%-%d+%-%d+%.jsonl$')) end
end)
test('routine age limit does not expire death archives', function()
    local r, s = fake()
    s.files[r.directory .. 'combat-1000000000-123456-0001.jsonl'] = 'old'
    s.files[r.directory .. 'incident-1000000000-123456-0001.jsonl'] = 'preserve'
    r:prune()
    assert(not s.files[r.directory .. 'combat-1000000000-123456-0001.jsonl'])
    assert(s.files[r.directory .. 'incident-1000000000-123456-0001.jsonl'])
end)
test('session names do not overwrite same-second reloads', function()
    local r, s, d = fake(); r:record('first', {}); r:flush()
    local second = storage.new({character = 'Smalls', directory = r.directory}, d)
    second:record('second', {}); second:flush()
    assert(second.session ~= r.session and s.files[r.current.path]:find('first'))
end)
test('new segments in a long session use their actual creation time', function()
    local r, s = fake({segment_bytes = 300})
    r:record('old', {}); r:flush(); s.now = s.now + 9 * 86400
    r:record('new', {}); r:record('new2', {}); r:flush(); r:prune()
    assert(r.current.name:find('combat-' .. tostring(s.now), 1, true))
    assert(s.files[r.current.path])
end)
test('unsafe character directories rejected', function()
    local _, _, d = fake()
    assert(not pcall(storage.new, {character = '../oops', directory = 'C:/capture'}, d))
end)
test('incident count and byte bounds', function()
    local r, s = fake({incidents = 2, incident_bytes = 1200, ring_bytes = 350})
    for i = 1, 5 do
        r:mark('manual')
        for n = 1, 15 do r:record('sample', {n = n}) end
        s.now = s.now + 700; r:tick({}, true)
    end
    r:close({}); r:prune()
    local count = 0
    for path, content in pairs(s.files) do
        if path:find('/incident%-') then count = count + 1; assert(#content <= 1200) end
    end
    assert(count <= 2)
end)
print(string.format('%d recorder tests passed', passed))
