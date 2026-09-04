-- ============================================================
--  Project SCLP Script -- one script, any SCLP tower game
--
--  These games are almost all EToH-kit fangames: same Framework kit, same
--  workspace.Towers[name] / Obby / WinPad / Teleporter layout. So rather than
--  carrying a per-game tower registry, this discovers towers from the world at
--  runtime and builds routes from the tower's own parts. An unlisted game works
--  exactly as well as a listed one -- Games.lua only supplies a display name.
--
--  Open menu: RightShift.
-- ============================================================

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local player     = Players.LocalPlayer
local currentPlaceId = game.PlaceId

if getgenv().SCLPScript and getgenv().SCLPScript.unload then
    pcall(getgenv().SCLPScript.unload)
end
local SCLP = { conns = {} }
getgenv().SCLPScript = SCLP

local REPO = "https://raw.githubusercontent.com/cslp1/Project-SCLP-Script/refs/heads/main/"

local function fetch(url)
    local src
    local ok = pcall(function() src = game:HttpGet(url .. "?cb=" .. tostring(os.time())) end)
    if ok and type(src) == "string" and #src > 0 then return src end
    return nil
end

-- ===== which game are we in =====
local GameInfo = { abbr = tostring(currentPlaceId), name = "Unknown place" }
do
    local src = fetch(REPO .. "Games.lua")
    if src then
        local fn = loadstring(src)
        if fn then
            local ok, tbl = pcall(fn)
            if ok and type(tbl) == "table" and tbl[currentPlaceId] then
                GameInfo = { abbr = tbl[currentPlaceId][1], name = tbl[currentPlaceId][2] }
            end
        end
    end
end

-- ===== per-game entry overrides =====
-- Loaded as data so a game with an unusual portal layout can be supported by editing
-- Portals.lua rather than this script.
local PortalOverride = {}
do
    local src = fetch(REPO .. "Portals.lua")
    if src then
        local fn = loadstring(src)
        if fn then
            local ok, tbl = pcall(fn)
            if ok and type(tbl) == "table" and tbl[currentPlaceId] then
                PortalOverride = tbl[currentPlaceId]
            end
        end
    end
end

local uiRepo = "https://raw.githubusercontent.com/deividcomsono/Obsidian/398653c103a0b4a8d2a3b68bcd383af21814a512/"
local Library      = loadstring(game:HttpGet(uiRepo .. "Library.lua"))()
local SaveManager  = loadstring(game:HttpGet(uiRepo .. "addons/SaveManager.lua"))()
local ThemeManager = loadstring(game:HttpGet(uiRepo .. "addons/ThemeManager.lua"))()

-- How far above a checkpoint's top surface the character is placed. 3 puts an R6 root
-- part at roughly standing height, but the character is CFrame-driven and never settles
-- onto anything, so it rides that gap for the whole run and may never physically contact
-- the surfaces it passes over. Towers that validate progress by touch (ToER counts which
-- FloorN parts you touched, and only checks at the WinPad) will reject a run that
-- traversed everything without ever registering. Lower it to put the body in contact.
local PLAYER_FOOT_OFFSET = 3
-- Returns a position on top of `part`'s surface, raised so the character stands
-- on top of it instead of clipping into the part. Accounts for the part's size
-- and orientation so it works for thick and rotated parts, not just thin ones.
local function getTopPos(part)
    local cf, size = part.CFrame, part.Size
    local halfTop = 0.5 * (
        math.abs(cf.UpVector.Y)    * size.Y +
        math.abs(cf.RightVector.Y) * size.X +
        math.abs(cf.LookVector.Y)  * size.Z
    )
    return part.Position + Vector3.new(0, halfTop + PLAYER_FOOT_OFFSET, 0)
end


-- Auto Play moves by writing HumanoidRootPart.CFrame, not by walking, so nothing about
-- the motion is physical. Cover a long hop in a short step and the character jumps tens
-- of studs per frame, passing clean through the kit's per-floor checkpoints without ever
-- overlapping them; the tower then sees a floor reached whose checkpoint never fired and
-- kicks for "doing the tower out of order". Cap how fast a step may be covered, letting
-- the run overrun its configured time rather than move faster than the kit can track.
-- ToER at its registered 3:05 kicked every attempt; stretched out, it ran clean.
local MAX_WALK_SPEED = 90   -- studs/second (~1.5 studs per frame at 60fps)

local function towerFolder(name)
    local towersFolder = workspace:FindFirstChild("Towers")
    return towersFolder and towersFolder:FindFirstChild(name)
end

-- Resolve a tower's entry teleporter parts. Tries EToH's exact nesting first
-- (Teleporter.Teleporter.TPFRAME / Teleporter.TeleportTo), then falls back to a recursive
-- search by name so towers in other games using the same JToH kit (e.g. The Eternal Abyss)
-- resolve even if the hierarchy differs. Returns nil if the folder/part is gone.
-- Tower games don't agree on what the entry portal is called. Observed so far:
--   EToH  Teleporter.Teleporter.TPFRAME
--   TEA   Portal            (siblings: Frame, WinPad, SpawnPad)
--   CSCD  TP                (siblings: Checkpoints, Frame, DO_NOT_MOVE_...)
-- Ordered most- to least-specific. Deliberately excludes Frame (the tower's base) and
-- WinPad (the finish, not the entry).
local PORTAL_NAMES = {
    "TPFRAME", "Portal", "TP", "TeleportTo", "Teleporter", "Entrance", "SpawnPad", "Spawn",
}
-- Substring pass for games not covered above. Same exclusions.
local PORTAL_HINTS = { "tpframe", "portal", "teleport", "entrance", "spawnpad" }

-- Callers need a BasePart (they read .CFrame/.Position/.Size), but these can be Models
-- or Folders, so resolve down to an actual part.
local function toBasePart(inst)
    if not inst then return nil end
    if inst:IsA("BasePart") then return inst end
    if inst:IsA("Model") and inst.PrimaryPart then return inst.PrimaryPart end
    return inst:FindFirstChildWhichIsA("BasePart", true)
end

local function resolveTPFrame(name)
    local f = towerFolder(name)
    if not f then return nil end

    -- This game's own layout first, if Portals.lua describes one. An explicit path beats
    -- guessing by name, and a game that reuses a common name for something else can be
    -- steered to the right part here rather than tripping over the generic list below.
    if PortalOverride.nested then
        local node = f
        for _, seg in ipairs(PortalOverride.nested) do
            node = node and node:FindFirstChild(seg)
        end
        local part = toBasePart(node)
        if part then return part end
    end
    if PortalOverride.names then
        for _, candidate in ipairs(PortalOverride.names) do
            local part = toBasePart(f:FindFirstChild(candidate, true))
            if part then return part end
        end
    end

    -- EToH's exact nesting next: cheapest, and unambiguous when it's there.
    local tp    = f:FindFirstChild("Teleporter")
    local inner = tp and tp:FindFirstChild("Teleporter")
    local exact = inner and inner:FindFirstChild("TPFRAME")
    if exact then
        local part = toBasePart(exact)
        if part then return part end
    end

    -- Then each known name, recursively, in priority order.
    for _, candidate in ipairs(PORTAL_NAMES) do
        local part = toBasePart(f:FindFirstChild(candidate, true))
        if part then return part end
    end

    -- Last resort: any part whose name merely looks like a portal.
    for _, descendant in ipairs(f:GetDescendants()) do
        if descendant:IsA("BasePart") then
            local lower = descendant.Name:lower()
            for _, hint in ipairs(PortalOverride.hints or {}) do
                if lower:find(hint, 1, true) then return descendant end
            end
            for _, hint in ipairs(PORTAL_HINTS) do
                if lower:find(hint, 1, true) then return descendant end
            end
        end
    end

    return nil
end
local function resolveTeleportTo(name)
    local f = towerFolder(name)
    if not f then return nil end
    local tp    = f:FindFirstChild("Teleporter")
    local exact = tp and tp:FindFirstChild("TeleportTo")
    local found = exact or f:FindFirstChild("TeleportTo", true)
    if found then return toBasePart(found) end
    -- Games with a single combined entry part (no separate TPFRAME + TeleportTo stage --
    -- e.g. TEA's Portal) have nothing named TeleportTo at all. Fall back to the same part
    -- resolveTPFrame found: the player is already standing on it from the walk-to loop
    -- above, so the "wait for teleport" touch fires right away.
    return resolveTPFrame(name)
end


local function findRouteRoot(part)
    local node = part
    while node and node.Parent do
        if node.Parent == workspace then return node, "workspace." .. node.Name end
        if node.Name == "Obby" and node.Parent and node.Parent.Parent == workspace:FindFirstChild("Towers") then
            return node, ("workspace.Towers[%q].Obby"):format(node.Parent.Name)
        end
        -- A checkpoint that isn't under the tower's Obby (ToER's route uses parts from
        -- other folders inside the tower) used to walk all the way up to workspace.Towers
        -- and index down from there -- "workspace.Towers:GetChildren()[7]". That index is
        -- not stable: towers stream in and out of workspace.Towers, so on a later run
        -- slot 7 can be a different tower entirely and the route walks into the wrong one.
        -- Stop at the tower folder and key it by name, exactly like the Obby case above.
        if node.Parent == workspace:FindFirstChild("Towers") then
            return node, ("workspace.Towers[%q]"):format(node.Name)
        end
        if node.Parent == workspace:FindFirstChild("Parts") then
            return node.Parent, "workspace.Parts"
        end
        node = node.Parent
    end
    return nil, nil
end

local function pathFromRouteRoot(part)
    local root, rootExpr = findRouteRoot(part)
    if not root then return nil end
    local segs, node = {}, part
    while node and node ~= root do
        local parent = node.Parent
        if not parent then return nil end
        local idx
        for i, c in ipairs(parent:GetChildren()) do
            if c == node then idx = i break end
        end
        if not idx then return nil end
        table.insert(segs, 1, (":GetChildren()[%d]"):format(idx))
        node = parent
    end
    if node ~= root then return nil end
    if node == root and root == part then return rootExpr end
    return rootExpr .. table.concat(segs)
end

-- Whether this game keeps a tower's obstacle parts in one shared top-level
-- workspace.Parts instead of a per-tower Obby (The Eternal Abyss does). Worked out from
-- the world rather than a list of place ids -- a hardcoded list would mean every new game
-- needs a code change, which defeats the point of this script.
--
-- Returning false is safe either way: collectAutoRoute tries Obby first and falls back to
-- workspace.Parts when that yields nothing, so a game that mixes both still resolves.
local function usesSharedParts()
    local towers = workspace:FindFirstChild("Towers")
    local parts  = workspace:FindFirstChild("Parts")
    return parts ~= nil and towers == nil
end

-- Direct children first: that's the usual layout and it keeps the emitted paths short.
-- But some towers group their obby into section Models, so the top level holds no
-- BaseParts at all -- fall back to the full descendant list instead of reporting the
-- container as empty (which is what "CoIV's Obby has no parts" was).
local function gatherParts(container)
    local direct = {}
    for _, v in ipairs(container:GetChildren()) do
        if v:IsA("BasePart") then direct[#direct + 1] = v end
    end
    if #direct > 0 then return direct end
    local all = {}
    for _, v in ipairs(container:GetDescendants()) do
        if v:IsA("BasePart") then all[#all + 1] = v end
    end
    return all
end

local function collectAutoRoute(name, descending)
    local folder = towerFolder(name)

    -- Where the obstacle parts live.
    local root, rootExpr
    local parts = {}
    local sharedOnly = usesSharedParts()

    -- In a shared-parts place (TEA) the Obby is deliberately never looked at, even if
    -- the tower folder happens to have one -- workspace.Parts is the live obby there.
    if not sharedOnly then
        local obby = folder and folder:FindFirstChild("Obby")
        if obby then
            root, rootExpr = obby, ("workspace.Towers[%q].Obby"):format(name)
            parts = gatherParts(obby)
        end
    end
    if #parts == 0 then
        local shared = workspace:FindFirstChild("Parts")
        if shared then
            root, rootExpr = shared, "workspace.Parts"
            parts = gatherParts(shared)
        end
    end
    if #parts == 0 then
        if sharedOnly then
            return nil, "Nothing in workspace.Parts -- this game only exposes a tower's parts while you're inside it, so enter the tower first."
        end
        if not folder and not workspace:FindFirstChild("Parts") then
            return nil, name .. " isn't loaded in workspace.Towers, and there's no workspace.Parts either."
        end
        return nil, ("No parts found for %s. Towers that keep their parts in workspace.Parts (e.g. The Eternal Abyss) only expose them while you're inside the tower -- enter it first."):format(name)
    end
    -- Floor-aware ordering. The kit kicks for doing a tower "out of order", and it
    -- tracks that per FLOOR -- so the route has to finish one floor before touching the
    -- next. Floors are never numbered anywhere, but the Frame is colour-banded per floor
    -- (the same signal the Floor Counter reads), so the lowest part of each colour marks
    -- where a floor begins. Sorting on raw height interleaves parts across those
    -- boundaries, which is precisely what puts the route out of order.
    local bands = {}
    do
        local frame = folder and folder:FindFirstChild("Frame")

        -- Best case: the tower NAMES its floors. ToGF's Frame holds Floor1..Floor10, and
        -- a number straight from the tower beats anything inferred -- no colour guessing,
        -- no merging of decoration into spurious floors.
        if frame then
            local function scanNamedFloors()
                local baseOfFloor = {}
                for _, v in ipairs(frame:GetDescendants()) do
                    if v:IsA("BasePart") then
                        local n = tonumber(v.Name:match("^[Ff]loor(%d+)$"))
                        if n then
                            local base = v.Position.Y - v.Size.Y / 2
                            if not baseOfFloor[n] or base < baseOfFloor[n] then
                                baseOfFloor[n] = base
                            end
                        end
                    end
                end
                local nums = {}
                for n in pairs(baseOfFloor) do nums[#nums + 1] = n end
                table.sort(nums)
                return baseOfFloor, nums
            end

            -- Streaming can still be filling in the Frame right after you enter a tower,
            -- so a scan taken too early comes back with gaps (ToER dropped Floor1 and
            -- Floor7 on the first pass). A missing floor number shifts every band after it
            -- down one slot, silently merging two real floors into a single bucket -- the
            -- exact kind of collision this ordering exists to prevent. Retry until the
            -- found numbers are contiguous, or give up after a few tries rather than
            -- building a route on a half-streamed tower.
            local baseOfFloor, nums = scanNamedFloors()
            for _ = 1, 5 do
                if #nums == 0 then break end
                local contiguous = true
                for i = 2, #nums do
                    if nums[i] ~= nums[i - 1] + 1 then contiguous = false break end
                end
                if contiguous then break end
                task.wait(0.75)
                baseOfFloor, nums = scanNamedFloors()
            end
            for _, n in ipairs(nums) do bands[#bands + 1] = baseOfFloor[n] end
            table.sort(bands)   -- the lookup below walks bands in ascending height
        end

        -- Otherwise fall back to the colour banding, for towers with unnamed floors.
        if frame and #bands == 0 then
            local lowestOfColour = {}
            for _, v in ipairs(frame:GetDescendants()) do
                if v:IsA("BasePart") then
                    local hex  = v.Color:ToHex()
                    local base = v.Position.Y - v.Size.Y / 2
                    if not lowestOfColour[hex] or base < lowestOfColour[hex] then
                        lowestOfColour[hex] = base
                    end
                end
            end
            for _, y in pairs(lowestOfColour) do bands[#bands + 1] = y end
            table.sort(bands)

            -- Distinct colours don't always mean distinct floors: trim, signs and
            -- decoration sit at their own heights and each opens a spurious floor a few
            -- studs above the real one -- ToGF reports six "floors" inside a 36-stud
            -- span. Merge bands too close together to be separate floors, sizing the
            -- threshold off this tower's own typical spacing rather than a fixed number,
            -- since floor heights differ from tower to tower.
            if #bands > 2 then
                local gaps = {}
                for i = 2, #bands do gaps[#gaps + 1] = bands[i] - bands[i - 1] end
                table.sort(gaps)
                local typical = gaps[math.max(1, math.floor(#gaps * 0.75))]
                local minGap  = math.max(10, typical * 0.45)

                local merged = { bands[1] }
                for i = 2, #bands do
                    if bands[i] - merged[#merged] >= minGap then
                        merged[#merged + 1] = bands[i]
                    end
                end
                bands = merged
            end
        end
    end

    -- Which floor a part belongs to: the last band starting at or below it. With no
    -- bands (no Frame, or one colour) everything lands on floor 1 and this reduces to
    -- the old height ordering rather than failing.
    local floorOf = {}
    for _, p in ipairs(parts) do
        local idx, y = 1, p.Position.Y
        for i = 1, #bands do
            if y >= bands[i] - 2 then idx = i else break end
        end
        floorOf[p] = idx
    end

    -- Ascending = climb (lowest floor first). Descending = a tower you go DOWN, so the
    -- highest floor is the start and the order flips.
    table.sort(parts, function(a, b)
        local fa, fb = floorOf[a], floorOf[b]
        if fa ~= fb then
            if descending then return fa > fb end
            return fa < fb
        end
        if descending then return a.Position.Y > b.Position.Y end
        return a.Position.Y < b.Position.Y
    end)

    -- Within a floor, height still isn't a path: parts at the same height sit on
    -- opposite sides of the tower, so consecutive checkpoints lurched across the map.
    -- Take the closest of the next few candidates instead -- but never look past the end
    -- of the current floor, or the route would start one floor before finishing another.
    local PROXIMITY_WINDOW = 30
    do
        local n    = #parts
        local used = table.create(n, false)
        local out  = table.create(n)
        local head, at = 1, nil

        for _ = 1, n do
            while head <= n and used[head] do head += 1 end
            if head > n then break end

            local floorHere = floorOf[parts[head]]
            local bestIdx   = head
            if at then
                local bestDist, seen, i = math.huge, 0, head
                while i <= n and seen < PROXIMITY_WINDOW do
                    if not used[i] then
                        if floorOf[parts[i]] ~= floorHere then break end
                        seen += 1
                        local d = (parts[i].Position - at).Magnitude
                        if d < bestDist then bestDist, bestIdx = d, i end
                    end
                    i += 1
                end
            end

            used[bestIdx] = true
            out[#out + 1] = parts[bestIdx]
            at = parts[bestIdx].Position
        end
        parts = out
    end

    -- Prefer the tower folder's own WinPad (TEA keeps one there next to Portal/Frame),
    -- then look inside the parts source for games that ship it with the obby instead.
    local winPad = folder and (folder:FindFirstChild("WinPad", true) or folder:FindFirstChild("Winpad", true))
    if not winPad then
        winPad = root:FindFirstChild("WinPad", true) or root:FindFirstChild("Winpad", true)
    end
    return { parts = parts, winPad = winPad, root = root, rootExpr = rootExpr }
end

-- ============================================================
--  ROUTES
-- ============================================================
-- A published route lives at Routes/<abbr>/<tower>.lua in this repo. Nothing has to exist
-- there: with no file, Automake Route builds one from the tower's own parts.
-- Abbreviations like "TC:L", "TWR$" and "bl:r" can't be folder names -- a colon is
-- illegal on Windows and both are awkward in a URL -- so routes are filed under a
-- stripped form. Keep this in step with the folder names in Routes/.
local function safeAbbr(a)
    return (a:gsub("[^%w%-_]", ""))
end

local function fetchRoute(towerName)
    local src = fetch(("%sRoutes/%s/%s.lua"):format(REPO, safeAbbr(GameInfo.abbr), towerName))
    if not src then return nil end
    local fn = loadstring(src)
    if not fn then return nil end
    local ok, getRoute = pcall(fn)
    if not ok or type(getRoute) ~= "function" then return nil end
    local ok2, route = pcall(getRoute)
    if not ok2 or type(route) ~= "table" then return nil end
    return route
end

-- ============================================================
--  WALKER
-- ============================================================
local running = false

local function hrpNow()
    local char = player.Character
    return char and char:FindFirstChild("HumanoidRootPart"), char
end

-- Ask the engine to run a part's touch handlers rather than relying on the CFrame-driven
-- body actually colliding. Kits score progress by counted touches, and a tweened character
-- can cross a part without the engine ever reporting contact.
local function forceTouch(part)
    if typeof(firetouchinterest) ~= "function" then return end
    local hrp = hrpNow()
    if not (hrp and part and part.Parent) then return end
    pcall(function()
        firetouchinterest(part, hrp, 0)
        firetouchinterest(part, hrp, 1)
    end)
end

local function buildSteps(checkpoints)
    local hrp = hrpNow()
    local prev = hrp and hrp.Position or Vector3.zero
    local steps = {}
    for _, step in ipairs(checkpoints) do
        if step == "jump" then
            table.insert(steps, { type = "jump" })
            continue
        end
        -- A wait carries no target, so it has to be handled before the target-required
        -- path below or it silently vanishes and the route loses its pauses.
        if type(step) == "table" and step.type == "wait" then
            table.insert(steps, { type = "wait", seconds = tonumber(step.seconds) or 1 })
            continue
        end
        local kind, target = "tween", nil
        if typeof(step) == "Instance" then
            target = step
        elseif type(step) == "table" then
            kind, target = step.type or "tween", step.target
        end
        if target and target:IsA("BasePart") then
            local dest = getTopPos(target)
            table.insert(steps, { type = kind, target = target, destPos = dest,
                                  dist = (dest - prev).Magnitude })
            prev = dest
        end
    end
    return steps
end

local function walk(steps, budget)
    local remaining, cum = {}, 0
    for i = #steps, 1, -1 do
        if steps[i].type == "tween" then cum = cum + (steps[i].dist or 0) end
        remaining[i] = cum
    end
    local deadline = os.clock() + math.max(budget or 180, 1)

    for i, step in ipairs(steps) do
        if not running then return false end
        local hrp, char = hrpNow()
        if not hrp then return false end

        if step.type == "jump" then
            local hum = char:FindFirstChildOfClass("Humanoid")
            if hum then hum.Jump = true end

        elseif step.type == "wait" then
            local untilT = os.clock() + step.seconds
            while running and os.clock() < untilT do task.wait() end

        elseif step.type == "teleport" then
            local dest = (step.target and step.target.Parent)
                and getTopPos(step.target) or step.destPos
            hrp.CFrame = CFrame.new(dest) * (hrp.CFrame - hrp.CFrame.Position)
            forceTouch(step.target)

        else
            -- Ported from EToH Script.lua's Auto Play walker.
            local dist       = (step.destPos - hrp.Position).Magnitude
            local timeLeft   = math.max(deadline - os.clock(), 0.001)
            local remainDist = remaining[i]
            local stepTime   = remainDist > 0 and (timeLeft * (dist / remainDist)) or 0.05
            stepTime         = math.max(stepTime, 0.05)
            -- Never let the budget dictate a speed the game can't track a touch at.
            stepTime         = math.max(stepTime, dist / MAX_WALK_SPEED)

            local startTime  = os.clock()
            local moveTarget = step.target
            -- A checkpoint that has drifted since the route resolved is a moving platform,
            -- and needs chasing rather than a tween to a stale position.
            local isMoving   = moveTarget and moveTarget.Parent and
                               (getTopPos(moveTarget) - step.destPos).Magnitude > 0.5
            local done       = false

            if not isMoving then
                local dest  = CFrame.new(step.destPos) * (hrp.CFrame - hrp.CFrame.Position)
                local tween = TweenService:Create(hrp, TweenInfo.new(stepTime, Enum.EasingStyle.Linear), { CFrame = dest })
                tween:Play()
                tween.Completed:Connect(function() done = true end)
                repeat task.wait() until done or not running
                tween:Cancel()
            else
                -- Arrival is by touch here: the platform is moving, so a distance check
                -- against a position sampled last frame is never quite right.
                local touchConn
                if moveTarget then
                    touchConn = moveTarget.Touched:Connect(function(hit)
                        local c = player.Character
                        if c and hit:IsDescendantOf(c) then done = true end
                    end)
                end
                local stepStartPos    = hrp.Position
                local maxStepProgress = 0
                local moveConn
                moveConn = RunService.Heartbeat:Connect(function(dt)
                    if not running then done = true moveConn:Disconnect() return end
                    local c = player.Character
                    local h = c and c:FindFirstChild("HumanoidRootPart")
                    if not h then done = true moveConn:Disconnect() return end
                    local currentDest = step.destPos
                    if moveTarget and moveTarget.Parent then
                        currentDest = getTopPos(moveTarget)
                    end
                    local currentDist = (currentDest - h.Position).Magnitude
                    if currentDist <= 0.1 then done = true moveConn:Disconnect() return end
                    local speed    = stepTime > 0 and (dist / stepTime) or 50
                    local moveDist = math.min(speed * dt, currentDist)
                    local rawDir   = (currentDest - h.Position)
                    if rawDir.Magnitude < 0.001 then return end
                    local dir = rawDir.Unit
                    if dir ~= dir then return end

                    -- Never let a physics correction erase progress already made toward
                    -- this checkpoint.
                    local totalVec = currentDest - stepStartPos
                    local totalLen = totalVec.Magnitude
                    local nextPos  = h.Position + dir * moveDist
                    if totalLen > 0.001 then
                        local routeDir = totalVec.Unit
                        local currentProgress = math.clamp((h.Position - stepStartPos):Dot(routeDir), 0, totalLen)
                        maxStepProgress = math.max(maxStepProgress, currentProgress)
                        local proposedProgress = math.clamp((nextPos - stepStartPos):Dot(routeDir), 0, totalLen)
                        proposedProgress = math.max(proposedProgress, math.min(maxStepProgress + moveDist, totalLen))
                        nextPos = stepStartPos + routeDir * proposedProgress
                        maxStepProgress = proposedProgress
                    end
                    h.CFrame = CFrame.new(nextPos)
                    if (os.clock() - startTime) >= stepTime then
                        h.CFrame = CFrame.new(currentDest)
                        done = true
                        moveConn:Disconnect()
                    end
                end)
                repeat task.wait() until done or not running
                if moveConn then moveConn:Disconnect() end
                if touchConn then touchConn:Disconnect() end
            end
            forceTouch(step.target)
        end
    end
    return true
end

-- Character-only noclip: enough to stop the body snagging on geometry while the tween
-- drives it, without touching the world's own collision.
local function setNoclip(on)
    if SCLP.noclip then SCLP.noclip:Disconnect() SCLP.noclip = nil end
    if not on then return end
    SCLP.noclip = RunService.Stepped:Connect(function()
        local char = player.Character
        if not char then return end
        for _, p in ipairs(char:GetDescendants()) do
            if p:IsA("BasePart") and p.CanCollide then p.CanCollide = false end
        end
    end)
end

-- ============================================================
--  UI
-- ============================================================
local Window = Library:CreateWindow({
    Title         = "Project SCLP Script",
    Footer        = ("%s  |  place %d"):format(GameInfo.name, currentPlaceId),
    NotifySide    = "Right",
    ToggleKeybind = Enum.KeyCode.RightShift,
    AutoShow      = true,
})
local Tabs = {
    Main     = Window:AddTab("Towers",   "house"),
    Settings = Window:AddTab("Settings", "settings"),
}
local Options = Library.Options

local TowerBox  = Tabs.Main:AddLeftGroupbox("Tower")
local ActionBox = Tabs.Main:AddRightGroupbox("Actions")

local function notify(text, dur)
    Library:Notify({ Title = "SCLP", Description = text, Duration = dur or 3 })
end

-- Towers come from the world, not a registry -- that is what makes this work in a game
-- nobody has catalogued.
local towerNames = {}
local function refreshTowers()
    local folder = workspace:FindFirstChild("Towers")
    local names = {}
    if folder then
        for _, c in ipairs(folder:GetChildren()) do names[#names + 1] = c.Name end
        table.sort(names)
    end
    -- Only push when the list actually changed, so the dropdown doesn't fight the user
    -- while it's open. Towers stream in and out constantly.
    if #names ~= #towerNames then
        towerNames = names
        pcall(function() Options.TowerSelect:SetValues(names) end)
        return
    end
    for i = 1, #names do
        if names[i] ~= towerNames[i] then
            towerNames = names
            pcall(function() Options.TowerSelect:SetValues(names) end)
            return
        end
    end
end

TowerBox:AddDropdown("TowerSelect", {
    Text    = "Tower",
    Values  = {},
    Default = "",
    Tooltip = "Every tower currently loaded in workspace.Towers.",
})
TowerBox:AddDropdown("RouteOrder", {
    Text    = "Automake order",
    Values  = { "Ascending", "Descending" },
    Default = "Ascending",
    Tooltip = "Ascending for a tower you climb, Descending for one you go down.",
})
TowerBox:AddInput("TimeBudget", {
    Text        = "Time budget (mm:ss)",
    Default     = "3:05",
    Placeholder = "3:05",
    Tooltip     = "How long the walk should take. Too short and the character outruns the game's own touch detection, which some towers reject.",
})
local statusLabel = TowerBox:AddLabel("Idle.", true)
local function setStatus(t) pcall(function() statusLabel:SetText(t) end) end

local function budgetSeconds()
    local v = Options.TimeBudget and Options.TimeBudget.Value or "3:05"
    local m, s = tostring(v):match("^(%d+):(%d+)$")
    if m then return tonumber(m) * 60 + tonumber(s) end
    return tonumber(v) or 185
end

local armedRoute = nil   -- set by Automake; preferred over a published file

ActionBox:AddButton({
    Text    = "Teleport to Tower",
    Tooltip = "Jump to the selected tower's entry, whatever this game calls it.",
    Func = function()
        local name = Options.TowerSelect and Options.TowerSelect.Value
        if not name or name == "" then notify("Pick a tower first.") return end
        local part = resolveTPFrame(name)
        if not part then notify(name .. ": no entry part found.", 5) return end
        local hrp = hrpNow()
        if not hrp then notify("No character.") return end
        hrp.CFrame = CFrame.new(part.Position + Vector3.new(0, 3, 0)) * (hrp.CFrame - hrp.CFrame.Position)
        forceTouch(part)
        notify("Moved to " .. name .. ".")
    end,
})

ActionBox:AddButton({
    Text    = "Automake Route",
    Tooltip = "Build a route from the selected tower's own parts, ordered floor by floor, and arm it.",
    Func = function()
        local name = Options.TowerSelect and Options.TowerSelect.Value
        if not name or name == "" then notify("Pick a tower first.") return end
        local descending = (Options.RouteOrder and Options.RouteOrder.Value) == "Descending"
        local data, err = collectAutoRoute(name, descending)
        if not data then notify(err or "Couldn't build a route.", 6) return end
        armedRoute = function()
            local fresh = collectAutoRoute(name, descending)
            local steps = {}
            if fresh then
                for _, p in ipairs(fresh.parts) do steps[#steps + 1] = p end
                if fresh.winPad then steps[#steps + 1] = fresh.winPad end
            end
            return steps
        end
        setStatus(("Armed %d checkpoints for %s."):format(#data.parts, name))
        notify(("%s: %d checkpoints%s, armed."):format(
            name, #data.parts, data.winPad and " + WinPad" or " (no WinPad)"), 5)
    end,
})

ActionBox:AddButton({
    Text    = "Auto Play",
    Tooltip = "Walk the armed route, or the published route for this tower if one exists.",
    Func = function()
        if running then notify("Already running.") return end
        local name = Options.TowerSelect and Options.TowerSelect.Value
        if not name or name == "" then notify("Pick a tower first.") return end
        task.spawn(function()
            running = true
            setNoclip(true)
            setStatus("Resolving route for " .. name .. "...")

            local checkpoints
            if armedRoute then
                checkpoints = armedRoute()
            else
                checkpoints = fetchRoute(name)
            end
            if not checkpoints or #checkpoints == 0 then
                notify("No route for " .. name .. ". Use Automake Route.", 6)
                setStatus("Idle.")
                running = false
                setNoclip(false)
                return
            end

            local steps = buildSteps(checkpoints)
            setStatus(("Walking %s -- %d steps."):format(name, #steps))
            local ok = walk(steps, budgetSeconds())
            setStatus(ok and (name .. " finished.") or (name .. " stopped."))
            if ok then notify(name .. " complete!", 4) end
            running = false
            setNoclip(false)
        end)
    end,
})

ActionBox:AddButton({
    Text    = "Stop",
    Tooltip = "Stop the current walk and restore collision.",
    Func = function()
        running = false
        setNoclip(false)
        setStatus("Stopped.")
    end,
})

ActionBox:AddButton({
    Text    = "Copy Route to Clipboard",
    Tooltip = "Copy the armed route as a .lua file you can commit to Routes/<game>/<tower>.lua.",
    Func = function()
        if not armedRoute then notify("Nothing armed -- run Automake Route first.") return end
        local name = Options.TowerSelect and Options.TowerSelect.Value
        local steps = armedRoute()
        local out = { "return function()", "    return {" }
        for _, p in ipairs(steps) do
            local path = pathFromRouteRoot and pathFromRouteRoot(p)
            out[#out + 1] = ("        %s,"):format(path or ("--[[ unresolved: %s ]] nil"):format(p.Name))
        end
        out[#out + 1] = "    }"
        out[#out + 1] = "end"
        local src = table.concat(out, "\n")
        if typeof(setclipboard) == "function" then
            setclipboard(src)
            notify(("Copied %d checkpoints for %s."):format(#steps, name), 4)
        else
            print(src)
            notify("No clipboard on this executor -- printed to console instead.", 5)
        end
    end,
})

-- ===== Settings =====
local SettingsBox = Tabs.Settings:AddLeftGroupbox("Script")
SettingsBox:AddLabel(("Game: %s (%s)"):format(GameInfo.name, GameInfo.abbr), true)
SettingsBox:AddLabel(("Place: %d"):format(currentPlaceId))
SettingsBox:AddLabel(("Routes folder: Routes/%s/"):format(safeAbbr(GameInfo.abbr)))
SettingsBox:AddButton({
    Text    = "Dump Tower Structure",
    Tooltip = "Print the selected tower's folder tree to the console, plus what the script currently resolves as its entry. Use this when a game's portals aren't found, then add its layout to Portals.lua.",
    Func = function()
        local name = Options.TowerSelect and Options.TowerSelect.Value
        if not name or name == "" then notify("Pick a tower first.") return end
        local f = towerFolder(name)
        if not f then
            warn(("[SCLP] no folder named '%s' in workspace.Towers"):format(name))
            notify(name .. " isn't loaded.", 4)
            return
        end
        print(("=== %s / %s (place %d) ==="):format(GameInfo.abbr, name, currentPlaceId))
        -- Two levels is enough to spot the entry: deeper is usually the obby itself.
        local function dump(node, depth, prefix)
            for _, c in ipairs(node:GetChildren()) do
                local extra = ""
                if c:IsA("BasePart") then
                    extra = (" [%.0f,%.0f,%.0f]"):format(c.Position.X, c.Position.Y, c.Position.Z)
                elseif #c:GetChildren() > 0 then
                    extra = (" (%d children)"):format(#c:GetChildren())
                end
                print(("%s%s (%s)%s"):format(prefix, c.Name, c.ClassName, extra))
                if depth > 0 and #c:GetChildren() <= 25 then
                    dump(c, depth - 1, prefix .. "    ")
                end
            end
        end
        dump(f, 2, "  ")
        local entry = resolveTPFrame(name)
        local dest  = resolveTeleportTo(name)
        print(("resolved entry : %s"):format(entry and entry:GetFullName() or "NONE"))
        print(("resolved dest  : %s"):format(dest and dest:GetFullName() or "NONE"))
        if not entry then
            print("No entry found. Add this place to Portals.lua with the right name or path.")
        end
        notify("Structure printed to console.", 4)
    end,
})

SettingsBox:AddButton({
    Text = "Unload",
    Func = function()
        running = false
        setNoclip(false)
        for _, c in ipairs(SCLP.conns) do pcall(function() c:Disconnect() end) end
        SCLP.conns = {}
        Library:Unload()
    end,
})

SCLP.unload = function()
    running = false
    setNoclip(false)
    for _, c in ipairs(SCLP.conns) do pcall(function() c:Disconnect() end) end
    SCLP.conns = {}
    pcall(function() Library:Unload() end)
end

ThemeManager:SetLibrary(Library)
SaveManager:SetLibrary(Library)
SaveManager:IgnoreThemeSettings()
SaveManager:SetFolder("SCLPScript")
ThemeManager:SetFolder("SCLPScript")
SaveManager:BuildConfigSection(Tabs.Settings)
ThemeManager:ApplyToTab(Tabs.Settings)
SaveManager:LoadAutoloadConfig()

-- Towers stream in and out as you move, so keep the list current.
refreshTowers()
table.insert(SCLP.conns, RunService.Heartbeat:Connect(function()
    if SCLP._next and os.clock() < SCLP._next then return end
    SCLP._next = os.clock() + 1
    pcall(refreshTowers)
end))

notify(("Loaded in %s -- %d towers found."):format(GameInfo.name, #towerNames), 5)
