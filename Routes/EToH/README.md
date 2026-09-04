# EToH routes

Imported from [`cslp1/Project-EToH-Script`](https://github.com/cslp1/Project-EToH-Script),
flattened from its per-ring folders since routes here are filed per game rather than per
category.

EToH is played across a place per ring and zone, so all of them map back to `EToH` in
`Games.lua` — otherwise a route recorded in Ring 1 would be filed under that ring's place
id and never found from anywhere else.

Not imported: `TheEternalAbyss` and the `XLRing*` folders. Those are separate games with
their own place ids, so their routes belong under `Routes/TEA/` and `Routes/EXL/`.
