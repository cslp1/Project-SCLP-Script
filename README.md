# Project SCLP Script

One script for the SCLP difficulty-chart tower games.

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/cslp1/Project-SCLP-Script/refs/heads/main/Loader.lua"))()
```

Menu opens on **RightShift**.

## Why one script works across ~240 games

They are nearly all EToH-kit fangames — same `Framework` kit, same
`workspace.Towers[name]` / `Obby` / `WinPad` / `Teleporter` layout. So instead of carrying
a tower registry per game, this reads the world:

- **Towers come from `workspace.Towers`**, refreshed every second as they stream in and out
- **Routes are built from the tower's own parts** by Automake Route, ordered floor by floor
- **`Games.lua` only supplies a display name.** An unlisted game works identically, it just
  reports its place id instead of a title

That means a game released tomorrow works without a code change.

## Handling structural differences

| Difference | Handling |
|---|---|
| Entry is `TPFRAME` + `TeleportTo`, or one combined part (`Portal`, `TowerStart`) | `resolveTeleportTo` falls back to the entry part when there's no separate `TeleportTo` |
| Parts in a per-tower `Obby`, or one shared `workspace.Parts` | Detected from the world, not a place-id list; `Obby` first, `workspace.Parts` as fallback |
| Floors named `FloorN`, or only colour-banded | Named floors win; otherwise colour bands, merged so decoration doesn't open spurious floors |

## Walking

The character is moved by writing `CFrame`, so a few things matter:

- **Speed is capped at 90 studs/s.** Left to the time budget alone, a long hop in a short
  step jumps tens of studs per frame and passes through a checkpoint without overlapping it.
  Kits that count touched checkpoints then reject the run at the finish.
- **`firetouchinterest` on every checkpoint**, so progress registers whether or not the
  tweened body actually collided.
- **`wait` and `teleport` steps are honoured**, so routes with timed platform pauses work.

## Routes

Published routes live at `Routes/<abbr>/<tower>.lua` and are optional. Auto Play uses an
armed Automake route if there is one, otherwise the published file. **Copy Route to
Clipboard** emits a file you can commit.

```lua
return function()
    return {
        workspace.Towers["ToA"].Obby:GetChildren()[12],
        workspace.Towers["ToA"].WinPad,
    }
end
```
