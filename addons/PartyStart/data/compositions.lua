-- PartyStart composition policy.
--
-- Tactical profiles (master/physical/accuracy/magic/safe) decide which buffs
-- and debuffs are wanted.  Compositions decide who is present, who may drive
-- combat, and which weapon/weapon-skill policy belongs to each character/job.
-- Character and job names are validated by PartyStart before any automation
-- is applied.

return {
    default = 'progression',

    aliases = {
        current = 'progression',
        new = 'progression',
        old = 'legacy',
        blu = 'progression-blu',
        hybrid = 'progression-blu',
    },

    compositions = {
        progression = {
            label = 'Progression: COR / PLD-WAR / DNC / BRD / RDM / GEO',
            command_leader = 'Dolomedes',
            puller = 'Tackleberry',
            roles = {
                tank = 'Tackleberry',
                primary_healer = 'Tackleberry',
                backup_healer = 'Smalls',
                emergency_healer = 'Kickpuncher',
            },
            expected_jobs = {
                Dolomedes = {main='COR'},
                Tackleberry = {main='PLD', sub_jobs={'WAR','BLU'}},
                Kickpuncher = {main='DNC'},
                Barneystinson = {main='BRD'},
                Smalls = {main='RDM'},
                Achoo = {main='GEO'},
            },
            attackers = {
                'Tackleberry', 'Kickpuncher', 'Barneystinson',
                'Smalls', 'Achoo',
            },
            offense = {
                Dolomedes = {
                    COR = {weapon_mode='DualSavage', ws='Savage Blade', tp=1000},
                },
                Tackleberry = {
                    PLD = {weapon_mode='Naegling', ws='Savage Blade', tp=1000},
                },
                Kickpuncher = {
                    DNC = {weapon_mode='Tauret', ws='Evisceration', tp=1000},
                },
                Barneystinson = {
                    BRD = {weapon_mode='DualSavage', ws='Savage Blade', tp=1000},
                },
                Smalls = {
                    RDM = {weapon_mode='Maxentius', ws='Black Halo', tp=1000},
                },
                Achoo = {
                    GEO = {weapon_mode='Maxentius', ws='Black Halo', tp=1000},
                },
            },
        },

        legacy = {
            label = 'Legacy: BLU / COR / RDM / BRD / WHM / GEO',
            command_leader = 'Dolomedes',
            puller = 'Dolomedes',
            roles = {
                tank = 'Dolomedes',
                primary_healer = 'Smalls',
                backup_healer = 'Kickpuncher',
            },
            expected_jobs = {
                Dolomedes = {main='BLU'},
                Tackleberry = {main='COR'},
                Kickpuncher = {main='RDM'},
                Barneystinson = {main='BRD'},
                Smalls = {main='WHM'},
                Achoo = {main='GEO'},
            },
            attackers = {
                'Tackleberry', 'Kickpuncher', 'Barneystinson',
                'Smalls', 'Achoo',
            },
            offense = {
                Dolomedes = {
                    BLU = {
                        weapon_mode='TizThib', ws='Expiacion', tp=1000,
                        aftermath={enabled=true, mode='active', type='lv3',
                            ws='Expiacion', duration=180},
                    },
                },
                Tackleberry = {
                    COR = {weapon_mode='Naegling', ws='Savage Blade', tp=1000},
                },
                Kickpuncher = {
                    RDM = {weapon_mode='Tauret', ws='Evisceration', tp=1000},
                },
                Barneystinson = {
                    BRD = {weapon_mode='DualSavage', ws='Savage Blade', tp=1000},
                },
                Smalls = {
                    WHM = {weapon_mode='Maxentius', ws='Black Halo', tp=1000},
                },
                Achoo = {
                    GEO = {weapon_mode='Maxentius', ws='Black Halo', tp=1000},
                },
            },
        },

        ['progression-blu'] = {
            label = 'Progression BLU: BLU / PLD-WAR / DNC / BRD / RDM / GEO',
            command_leader = 'Dolomedes',
            puller = 'Tackleberry',
            roles = {
                tank = 'Tackleberry',
                primary_healer = 'Tackleberry',
                backup_healer = 'Smalls',
                emergency_healer = 'Kickpuncher',
            },
            expected_jobs = {
                Dolomedes = {main='BLU'},
                Tackleberry = {main='PLD', sub_jobs={'WAR','BLU'}},
                Kickpuncher = {main='DNC'},
                Barneystinson = {main='BRD'},
                Smalls = {main='RDM'},
                Achoo = {main='GEO'},
            },
            attackers = {
                'Tackleberry', 'Kickpuncher', 'Barneystinson',
                'Smalls', 'Achoo',
            },
            offense = {
                Dolomedes = {
                    BLU = {
                        weapon_mode='TizThib', ws='Expiacion', tp=1000,
                        aftermath={enabled=true, mode='active', type='lv3',
                            ws='Expiacion', duration=180},
                    },
                },
                Tackleberry = {
                    PLD = {weapon_mode='Naegling', ws='Savage Blade', tp=1000},
                },
                Kickpuncher = {
                    DNC = {weapon_mode='Tauret', ws='Evisceration', tp=1000},
                },
                Barneystinson = {
                    BRD = {weapon_mode='DualSavage', ws='Savage Blade', tp=1000},
                },
                Smalls = {
                    RDM = {weapon_mode='Maxentius', ws='Black Halo', tp=1000},
                },
                Achoo = {
                    GEO = {weapon_mode='Maxentius', ws='Black Halo', tp=1000},
                },
            },
        },
    },
}
