# Routes

Published routes, one file per tower:

```
Routes/<game abbr>/<tower name>.lua
```

The abbreviation is the one in `Games.lua`, with anything that isn't a letter, digit, `-`
or `_` stripped — `TC:L` becomes `TCL`, `TWR$` becomes `TWR`, `bl:r` becomes `blr`. The
script shows the exact folder for the game you're in under **Settings → Routes folder**.

The tower name must match its folder in `workspace.Towers` exactly, since that's what the
script looks up.

## Format

A file returns a function returning a list of checkpoints:

```lua
return function()
    return {
        workspace.Towers["ToA"].Obby:GetChildren()[12],
        workspace.Towers["ToA"].Obby:GetChildren()[45],
        "jump",
        { type = "wait", seconds = 1 },
        { type = "teleport", target = workspace.Towers["ToA"].Obby:GetChildren()[80] },
        workspace.Towers["ToA"].WinPad,
    }
end
```

A step can be:

| Step | Meaning |
|---|---|
| a `BasePart` | walk to the top of it |
| `"jump"` | jump on the spot |
| `{ type = "wait", seconds = n }` | pause, for a platform that has to come to you |
| `{ type = "teleport", target = part }` | move there instantly instead of walking |

## Getting one

Select the tower, press **Automake Route**, then **Copy Route to Clipboard**, and commit
what it gives you. Automake orders parts floor by floor rather than by raw height, since
kits kick for finishing a tower out of order.

## A note on indices

`:GetChildren()[N]` is how these come out, and it is not stable in every case — child
order can differ between sessions when parts stream in and out. Name-keyed roots
(`workspace.Towers["ToA"].Obby`) are safe; an index into `workspace.Towers` itself is not,
because towers load and unload as you move. If a route works and later stops, that's the
first thing to suspect.
