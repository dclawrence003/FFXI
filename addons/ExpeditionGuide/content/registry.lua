-- Authoritative pack registry. Established declarations are immutable;
-- route/profile modules are protected and discovered without registry edits.

return {
    schema=1,
    reserved_aliases={
        onboarding='sortie-onboarding-core',
        unlocks='sortie-onboarding-core',
        core='sortie-onboarding-core',
        sheetd='sortie-onboarding-sheet-d',
        dclear='sortie-sheet-d-demisang-live',
        sheetdlive='sortie-sheet-d-demisang-live',
        boss2='sortie-two-boss-c-a-training',
        twoboss='sortie-two-boss-c-a-training',
        ca='sortie-two-boss-c-a-training',
        run='sortie-main-run',
        mainrun='sortie-main-run',
        therun='sortie-main-run',
    },
    packs={
        {
            id='sortie',
            -- Pack guidance may later include the entry and postflight hubs;
            -- only instance_zones can satisfy live-run evidence.
            allowed_zones={
                [133]=true, [189]=true, [275]=true,
                [267]=true, [281]=true,
            },
            instance_zones={[133]=true, [189]=true, [275]=true},
            run_seconds=3600,
            stale_run_seconds=7200,
            catalog_revision=2,
            items='content.sortie.items',
            key_items='content.sortie.key_items',
            landmarks='content.sortie.landmarks',
            objectives='content.sortie.objectives',
            reward_scopes='content.sortie.reward_scopes',
            route_directory='content\\sortie\\routes\\',
            route_module_prefix='content.sortie.routes.',
            profile_directory='content\\sortie\\profiles\\',
            profile_module_prefix='content.sortie.profiles.',
            -- These frozen seed declarations are a fallback for test runtimes
            -- without directory enumeration. New content is discovered and
            -- never requires this registry to be edited.
            profile_modules={
                {module='content.sortie.profiles.objective_c_device_kill',
                    path='content\\sortie\\profiles\\objective_c_device_kill.lua',
                    identity='sortie_objective_c_device_kill'},
                {module='content.sortie.profiles.objective_d_demisang_clear',
                    path='content\\sortie\\profiles\\objective_d_demisang_clear.lua',
                    identity='sortie_objective_d_demisang_clear'},
            },
            routes={
                {module='content.sortie.routes.onboarding_core',
                    path='content\\sortie\\routes\\onboarding_core.lua',
                    identity='sortie-onboarding-core',
                    aliases={'onboarding','unlocks','core'}},
                {module='content.sortie.routes.onboarding_sheet_d',
                    path='content\\sortie\\routes\\onboarding_sheet_d.lua',
                    identity='sortie-onboarding-sheet-d',
                    aliases={'sheetd'}},
            },
        },
    },
}
