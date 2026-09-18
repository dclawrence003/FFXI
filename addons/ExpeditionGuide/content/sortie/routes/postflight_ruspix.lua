-- Postflight claim guide for the party's first completed Sortie foray.

return {
    schema=1,
    id='sortie-postflight-ruspix',
    version='0.1.0',
    title="Sortie Postflight: Ruspix's Plate",
    content='sortie',
    allowed_zones={[281]=true},
    guide_only=true,
    steps={
        {
            id='claim_ruspix', area='LEAFALLIA',
            completion={kind='all_key_item', item='ruspix_plate', auto=true},
            instruction="After the party's first completed foray, keep the exact six-person party together in Leafallia. Tackleberry, Kickpuncher, Barneystinson, Smalls, and Achoo each speak to Ruspix. Dolomedes also speaks unless his own key-item list confirms that he already holds Ruspix's plate.",
            warning="Only fresh all-six Ruspix's plate evidence completes this route. Entry plates should normally be Dull immediately post-run; Dull is diagnostic, not reward proof.",
        },
    },
}
