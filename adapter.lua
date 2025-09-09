--[[
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@                                                                              @@
@@  Adapter                                                                     @@
@@                                                                              @@
@@  This allows using the same source code for both WoW Classic and older       @@
@@  versions, such as WotLK 3.3.5 clients like you see in Project Epoch.        @@
@@                                                                              @@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
]]

local ADDONNAME, ns = ...
if not ns then
    -- Namespace not available in Wrath, so we fallback:
    _G[ADDONNAME] = _G[ADDONNAME] or {}
    ns = _G[ADDONNAME]
end

local L = ns.L

ns.adapter = {}
local adapter = ns.adapter

local PRIMARY_PROF_SPELLS = {
    2259,   -- Alchemy
    2018,   -- Blacksmithing
    7411,   -- Enchanting
    4036,   -- Engineering
    2366,   -- Herbalism
    45357,  -- Inscription (WotLK only, safe to include)
    2108,   -- Leatherworking
    2575,   -- Mining
    8613,   -- Skinning
    3908,   -- Tailoring
}

local SECONDARY_PROF_SPELLS = {
    2550,   -- Cooking
    3273,   -- First Aid
    7620,   -- Fishing
}

-- Feature detection -----------------------------------------------------------

adapter.isModern  = false
adapter.isWotLK   = false
adapter.isVanilla = false

if type(C_Timer) == "table" then
    adapter.isModern = true
elseif type(select) ~= "function" then
    adapter.isVanilla = true
elseif type(UnitAura) == "function" then
    adapter.isWotLK = true
end

-- Code to support timers ------------------------------------------------------

local waitTable = {}
local waitFrame = CreateFrame("Frame")
waitFrame:SetScript("OnUpdate", function(self, elapsed)
    local i = 1
    while i <= table.getn(waitTable) do
        local t = waitTable[i]
        if t.time <= elapsed then
            -- time elapsed → call
            t.func()
            table.remove(waitTable, i)
        else
            t.time = t.time - elapsed
            i = i + 1
        end
    end
end)

-- Adapter functions -----------------------------------------------------------

function adapter:dumpTable(table)
    if type(DevTools_Dump) == 'function' then
        DevTools_Dump(table)
        print(' ')
    else
        local function recursiveDump(t, indent)
            indent = indent or ""
            for k, v in pairs(t) do
                if type(v) == "table" then
                    print(indent .. '[' .. tostring(k) .. '] = {')
                    recursiveDump(v, indent .. '  ')
                    print(indent .. "}")
                elseif type(v) == "string" then
                    print(indent .. '[' .. tostring(k) .. '] = "' .. v .. '"')
                else
                    print(indent .. '[' .. tostring(k) .. '] = ' .. tostring(v))
                end
            end
        end
        recursiveDump(table)
        print(' ')
    end
end

function adapter:getContainerNumSlots(bagIndex)
    if C_Container then
        return C_Container.GetContainerNumSlots(bagIndex)
    else
        return GetContainerNumSlots(bagIndex)
    end
end

function adapter:getContainerItemLink(bagIndex, slotIndex)
    if C_Container then
        return C_Container.GetContainerItemLink(bagIndex, slotIndex)
    else
        return GetContainerItemLink(bagIndex, slotIndex)
    end
end

function adapter:playSound(soundFile, channel)
    channel = channel or "Master"  -- default channel

    if type(soundFile) == "string" then
        -- Try PlaySoundFile with channel first
        if type(PlaySoundFile) == "function" then
            local ok = pcall(function() PlaySoundFile(soundFile, channel) end)
            if ok then return end
            -- If it fails (e.g., client doesn’t accept channel), try without channel
            pcall(function() PlaySoundFile(soundFile) end)
            return
        end
        -- Fallback to legacy PlaySound
        if type(PlaySound) == "function" then
            pcall(function() PlaySound(soundFile) end)
            return
        end
    elseif type(soundFile) == "number" then
        -- Try PlaySound with channel first
        if type(PlaySound) == "function" then
            local ok = pcall(function() PlaySound(soundFile, channel) end)
            if ok then return end
            -- If it fails (e.g., client doesn’t accept channel), try without channel
            pcall(function() PlaySound(soundFile) end)
            return
        end
    end

    -- No-op if all of the above failed.
end

function adapter:getBuff(unit, index)
    local a = {UnitBuff(unit, index)}
    if not a or not a[1] then return nil end
    if type(a[2]) == 'string' then
        -- Older version that returns the rank string as the 2nd element.
        return {name=a[1], count=1, dispelType=a[5], duration=a[6], expirationTime=a[7], caster=a[8], spellId=a[11]}
    else
        -- Modern version where a[2] is a number.
        return {name=a[1], count=a[3], dispelType=a[4], duration=a[5], expirationTime=a[6], caster=a[7], spellId=a[10]}
    end
end

function adapter:getBuffs(unit)
    local buffs = {}
    local i = 1
    while true do
        local buff = adapter:getBuff(unit, i)
        if not buff or not buff.name then break end
        buffs[buff.name] = buff
        i = i + 1
    end
    return buffs
end

function adapter:getCombatLogInfo()
    if type(CombatLogGetCurrentEventInfo) == 'function' then
        -- https://warcraft.wiki.gg/wiki/COMBAT_LOG_EVENT
        a = {CombatLogGetCurrentEventInfo()}
        local t = {}
        t.timestamp         = a[1]  -- number: seconds since login
        t.subEvent          = a[2]  -- string: e.g. "SPELL_CAST_SUCCESS", "SWING_DAMAGE"
        t.hideCaster        = a[3]  -- always false in WotLK
        t.sourceGUID        = a[4]  -- string: "Player-..." / "Creature-..." / "Pet-..."
        t.sourceName        = a[5]  -- localized name or nil
        t.sourceFlags       = a[6]  -- bitfield, see COMBATLOG_OBJECT_* constants
        t.sourceRaidFlags   = a[7]  -- raid target icon flags (bitmask)
        t.destGUID          = a[8]  -- string
        t.destName          = a[9]  -- localized name or nil
        t.destFlags         = a[10] -- bitfield
        t.destRaidFlags     = a[11] -- raid target icon flags
        t.spellId           = a[12]
        t.spellName         = a[13]
        t.spellSchool       = a[14]
        if t.subEvent == "SPELL_AURA_APPLIED" or t.subEvent == "SPELL_AURA_REMOVED" or t.subEvent == "SPELL_AURA_REFRESH" then
            t.auraType      = a[15]
            t.auraAmount    = a[16]
        end
        return t
    else
        local t = arg
        t.timestamp         = a[1]  -- number: seconds since login
        t.subEvent          = a[2]  -- string: e.g. "SPELL_CAST_SUCCESS", "SWING_DAMAGE"
        t.hideCaster        = false -- always false in WotLK
        t.sourceGUID        = a[3]  -- string: "Player-..." / "Creature-..." / "Pet-..."
        t.sourceName        = a[4]  -- localized name or nil
        t.sourceFlags       = 0     -- bitfield, see COMBATLOG_OBJECT_* constants
        t.sourceRaidFlags   = 0     -- raid target icon flags (bitmask)
        t.destGUID          = a[6]  -- string
        t.destName          = a[7]  -- localized name or nil
        t.destFlags         = 0     -- bitfield
        t.destRaidFlags     = 0     -- raid target icon flags
        t.spellId           = a[9]
        t.spellName         = a[10]
        t.spellSchool       = nil
        if t.subEvent == "SPELL_AURA_APPLIED" or t.subEvent == "SPELL_AURA_REMOVED" or t.subEvent == "SPELL_AURA_REFRESH" then
            t.auraType      = a[12]
            t.auraAmount    = nil
        end
        return t
    end
end

function adapter:isSpellKnown(spellId)
    if type(IsPlayerSpell) == "function" then -- present on modern & Wrath
        return IsPlayerSpell(spellId)
    elseif type(IsSpellKnown) == "function" then -- present on Classic/Wrath
        return IsSpellKnown(spellId)
    else -- Extremely old fallback (unlikely needed in Classic/WotLK)
        local name = GetSpellInfo(spellId)
        return name and IsUsableSpell(name) ~= nil
    end
end

-- Returns the number of primary professions & the number of secondary professions.
function adapter:getNumProfessions()
    local nPrimary = 0
    for _, id in ipairs(PRIMARY_PROF_SPELLS) do
        if adapter:isSpellKnown(id) then
            nPrimary = nPrimary + 1
        end
    end

    local nSecondary = 0
    for _, id in ipairs(SECONDARY_PROF_SPELLS) do
        if adapter:isSpellKnown(id) then
            nSecondary = nSecondary + 1
        end
    end

    return nPrimary, nSecondary
end

function adapter:after(delay, func)
    if C_Timer and type(C_Timer.After) == "function" then
        C_Timer.After(delay, func)
    else
        table.insert(waitTable, { time = delay, func = func })
    end
end
