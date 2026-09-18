# Lottery compatibility for SalvageCells

Windower's Lottery addon broadcasts a pass request to every local client whenever
one client lots a treasure-pool slot. That is useful for ordinary single-winner
loot, but it conflicts with `SalvageCells`: several characters may still need the
same imbued cell and should be allowed to lot it.

`salvagecells-compat.patch` makes Lottery ignore item IDs 5365-5384 while keeping
its original behavior for every other item. Apply it to
`Windower/addons/lottery/lottery.lua`, then reload Lottery on every client.

Salvage cell names must also be absent from Treasury's Lot, Pass, and Drop lists.
Treasury treats items on its Drop list as pass targets while they are still in
the treasure pool, then drops them if they reach inventory.

The upstream Lottery copyright and BSD license remain in the patched source.

