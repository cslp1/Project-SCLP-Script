-- Project SCLP Script -- loader.
local URL = "https://raw.githubusercontent.com/cslp1/Project-SCLP-Script/refs/heads/main/SCLP.lua"
local ok, src = pcall(function() return game:HttpGet(URL .. "?cb=" .. tostring(os.time())) end)
if not ok or not src or #src == 0 then
    warn("[SCLP] couldn't fetch the script.")
    return
end
local fn, err = loadstring(src)
if not fn then
    warn("[SCLP] parse failed: " .. tostring(err))
    return
end
return fn()
