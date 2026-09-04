-- Per-game entry-part overrides.
--
-- The script already tries EToH's exact nesting, then a list of common names, then a
-- substring pass -- which covers most kit fangames. This file is for the ones it doesn't:
-- add the place id and the names that game actually uses, and it works without a code
-- change.
--
--   names  : exact child names to look for, recursively, in priority order.
--            Tried BEFORE the built-in list, so a game that reuses a common name for
--            something else can still be steered to the right part.
--   hints  : lowercase substrings, tried after the names.
--   nested : an explicit path from the tower folder down to the entry part, for layouts
--            where the name alone is ambiguous. Each element is a child name.
--
-- Use the "Dump Tower Structure" button in the Settings tab to see what a game actually
-- has, then add it here.
return {
    -- Eternal Towers of Hell -- Teleporter.Teleporter.TPFRAME
    [8562822414] = {
        nested = { "Teleporter", "Teleporter", "TPFRAME" },
    },

    -- The Eternal Abyss -- one combined Portal part, no separate TeleportTo stage
    [15873244701] = {
        names = { "Portal" },
    },

    -- EToH XL / XXL / XS -- TowerStart, sometimes in a top-level TowerPortals folder
    [13218032675] = { names = { "TowerStart", "Portal" } },
    [17846926884] = { names = { "TowerStart", "Portal" } },
    [18358123333] = { names = { "TowerStart", "Portal" } },

    -- Pit of Misery: XL
    [14894545694] = { names = { "TowerStart", "Portal" } },

    -- Caleb's Soul Crushing Domain -- TP rather than TPFRAME
    [10283991824] = { names = { "TP", "Portal" } },
}
