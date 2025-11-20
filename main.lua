local ADDONNAME, ns = ...
if not ns then
    -- Namespace not available in Wrath, so we fallback:
    _G[ADDONNAME] = _G[ADDONNAME] or {}
    ns = _G[ADDONNAME]
end

local L = ns.L
local adapter = ns.adapter

local dbg = false -- This should only be true if debugging.
local function printnothing() end
local pdb = dbg and print or printnothing

-- Constants
local ERROR_SOUND_FILE = "Interface\\AddOns\\" .. ADDONNAME .. "\\Sounds\\ding.wav"

SLASH_IRONMANCHALLENGE1, SLASH_IRONMANCHALLENGE2 = '/ironman', '/iron'
SlashCmdList["IRONMANCHALLENGE"] = function(str)
    ns:parseCommand(str)
end

-- Internal states
local _initialized = false
local _secondsSinceLastUpdate = 0
local _lastErrorCount = 0
local _waitingToCheckAll = false
local _checkAddonsCount = 0

--[[
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@                                                                              @@
@@  Items the player should not have in their bags                              @@
@@                                                                              @@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
]]

local FORBIDDEN_ITEMS = {
    -- Potions
    [13506]=1, [3386]=1, [3387]=1, [13444]=1, [5634]=1, [9030]=1, [5816]=1,
    [13459]=1, [13458]=1, [9172]=1, [13457]=1, [2459]=1, [3823]=1, [13442]=1,
    [929]=1, [13446]=1, [13456]=1, [13455]=1, [1710]=1, [3928]=1, [13461]=1,
    [20008]=1, [3827]=1, [6052]=1, [6372]=1, [6149]=1, [13443]=1, [858]=1,
    [6048]=1, [13462]=1, [5631]=1, [5633]=1, [6049]=1, [118]=1, [18841]=1,
    [18253]=1, [20002]=1, [3385]=1, [12190]=1, [4623]=1, [2455]=1, [6051]=1,
    [17348]=1, [6050]=1, [2456]=1, [13460]=1, [9144]=1, [23579]=1, [18839]=1,
    [4596]=1, [17351]=1, [3087]=1, [5632]=1, [17349]=1, [17352]=1, [1450]=1,
    [23698]=1, [23696]=1, [23578]=1,
    -- Flasks
    [13510]=1, [13512]=1, [13511]=1, [13513]=1, [2593]=1,
    -- Elixirs
    [8410]=1, [20079]=1, [12820]=1, [8412]=1, [13452]=1, [20007]=1, [8411]=1,
    [8529]=1, [13454]=1, [3388]=1, [3825]=1, [8423]=1, [20081]=1, [21546]=1,
    [9206]=1, [9088]=1, [3389]=1, [13445]=1, [5996]=1, [9264]=1, [8949]=1,
    [17708]=1, [9187]=1, [13453]=1, [20004]=1, [8424]=1, [9197]=1, [9154]=1,
    [3826]=1, [8827]=1, [9224]=1, [20080]=1, [8951]=1, [9155]=1, [13447]=1,
    [2457]=1, [9179]=1, [6662]=1, [3391]=1, [10592]=1, [6373]=1, [3383]=1,
    [2458]=1, [3390]=1, [18294]=1, [2454]=1, [3382]=1, [3828]=1, [9233]=1,
    [5997]=1,
    -- Healthstones
    [5509]=1, [5510]=1, [5511]=1, [5512]=1, [9421]=1, [19004]=1, [19005]=1,
    [19006]=1, [19007]=1, [19008]=1, [19009]=1, [19010]=1, [19011]=1,
    [19012]=1, [19013]=1,
}

--[[
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@                                                                              @@
@@  Map & minimap stuff                                                         @@
@@                                                                              @@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
]]

local _worldMapFrame -- late-bound for safety across versions
local _minimapRoot   -- MinimapCluster (Classic/Wrath/Retail) or fallback to Minimap
local _hookedToggleWorldMap

local function getMapFrames()
    if not _worldMapFrame then
        _worldMapFrame = _G._WorldMapFrame or _G._WorldMapFrameBase or _G.UI_WorldMapFrame
    end
    if not _minimapRoot then
        _minimapRoot = _G.MinimapCluster or _G.Minimap
    end
end

local function hideWorldMapImmediate()
    if _worldMapFrame and _worldMapFrame:IsShown() then
        _worldMapFrame:Hide()
    end
end

local function hideMinimapImmediate()
    if _minimapRoot and _minimapRoot:IsShown() then
        _minimapRoot:Hide()
    end
end

-- Guard World Map from being shown if nec.
local function guardWorldMap()
    if not _worldMapFrame then return end
    if not _worldMapFrame._noMapsHooked then
        _worldMapFrame:HookScript("OnShow", function(self)
            if not IronmanUserData.AllowMaps then
                self:Hide()
            end
        end)
        _worldMapFrame._noMapsHooked = true
    end
end

-- Guard Minimap from being shown if nec.
local function guardMinimap()
    if not _minimapRoot then return end
    if not _minimapRoot._noMapsHooked then
        _minimapRoot:HookScript("OnShow", function(self)
            if not IronmanUserData.AllowMaps then
                self:Hide()
            end
        end)
        _minimapRoot._noMapsHooked = true
    end
end

-- Classic/Wrath toggle key “M” calls this; Retail still defines it.
-- We can’t prevent execution, but we can immediately re-hide.
local function hookToggleWorldMap()
    if _G.ToggleWorldMap and not _hookedToggleWorldMap then
        hooksecurefunc("ToggleWorldMap", function()
            if not IronmanUserData.AllowMaps then
                hideWorldMapImmediate()
            end
        end)
        _hookedToggleWorldMap = true
    end
end

local function initMaps()
    -- Bind frames and hooks once the UI is ready.
    getMapFrames()
    guardWorldMap()
    guardMinimap()
    hookToggleWorldMap()
    -- Apply initial state.
    if not IronmanUserData.AllowMaps then
        hideWorldMapImmediate()
        hideMinimapImmediate()
    end
end

--[[
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@                                                                              @@
@@  Events                                                                      @@
@@                                                                              @@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
]]

-- This event handler table exclusively contains the all functions we use to process events for this lib.
local EV = {
    AUCTION_HOUSE_SHOW   = function() ns:warn(L.err_no_ah, true, true) end,
    BAG_UPDATE_DELAYED   = function() ns:checkAllDelayed() end,
    LEARNED_SPELL_IN_TAB = function() ns:checkAllDelayed() end,
    MAIL_SHOW            = function() ns:warn(L.err_no_mail, true, true) end,
    PLAYER_DEAD          = function() ns:died() end,
    PLAYER_LOGIN         = function() ns:init() end,
    UNIT_AURA            = function() ns:checkAllDelayed() end,
    UNIT_PET             = function() ns:checkAllDelayed() end,
}

local eventFrame = CreateFrame('frame', ADDONNAME .. "_Events")

-- Register all EV events.
for name in pairs(EV) do
    eventFrame:RegisterEvent(name)
end

-- Handle each EV event.
eventFrame:SetScript("OnEvent", function(self, event, ...)
    local func = EV[event]
    if func then func(self, ...) end
end)

-- Function to be executed on each screen update.
eventFrame:SetScript('OnUpdate', function(self, elapsed)
    if not _initialized then return end
    _secondsSinceLastUpdate = _secondsSinceLastUpdate + elapsed
    if _secondsSinceLastUpdate > IronmanUserData.Interval then
        ns:checkAll()
        _secondsSinceLastUpdate = 0
    end
end)

--[[
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@                                                                              @@
@@  Command line parsing                                                        @@
@@                                                                              @@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
]]

function ns:parseCommand(str)
    local p1, p2, match

    ns:initDB()

    p1, p2, match = str:find("^(%d+)$")
    if p1 then
        local n = tonumber(match)
        if n < 15 or n > 300 then
            ns:warn(L.err_seconds_ij(15, 300))
            return
        end
        IronmanUserData.Interval = n
        ns:success(L.checking_every_n(n))
        return
    end

    -----

    p1, p2 = str:find("^on$")
    if p1 then
        IronmanUserData.Suppress = false
        ns:success(L.checking_on)
        ns:checkAll()
        return
    end

    p1, p2 = str:find("^off$")
    if p1 then
        IronmanUserData.Suppress = true
        ns:success(L.checking_off)
        return
    end

    -----

    local function setMaps(tf)
        tf = tf or not IronmanUserData.AllowMaps

        if tf then
            if IronmanUserData.AllowPets then
                ns:warn(L.err_disable_pets("/iron pets"))
                return
            end
            if IronmanUserData.AllowTalents then
                ns:warn(L.err_disable_talents("/iron talents"))
                return
            end
        end

        IronmanUserData.AllowMaps = tf

        getMapFrames()
        guardWorldMap()
        guardMinimap()

        if not IronmanUserData.AllowMaps then
            hideWorldMapImmediate()
            hideMinimapImmediate()
        else
            -- Allow showing again; hooks remain but are no-ops while disabled.
            if _minimapRoot then _minimapRoot:Show() end
        end
        ns:success(IronmanUserData.AllowMaps and L.maps_on or L.maps_off)
        ns:success(L.description())
        print(" ")
    end

    p1, p2, match = str:find("^maps? *(%a*)$")
    if p1 then
        match = match:lower()
        if match == 'on' then
            setMaps(true)
        elseif match == 'off' then
            setMaps(false)
        else
            setMaps(nil)
        end
        return
    end

    -----

    local function setPets(tf)
        tf = tf or not IronmanUserData.AllowPets

        if tf then
            if IronmanUserData.AllowMaps then
                ns:warn(L.err_disable_maps("/iron maps"))
                return
            end
            if IronmanUserData.AllowTalents then
                ns:warn(L.err_disable_talents("/iron talents"))
                return
            end
        end

        IronmanUserData.AllowPets = tf

        ns:success(IronmanUserData.AllowPets and L.pets_on or L.pets_off)
        ns:success(L.description())
        ns:checkPets()
        print(" ")
    end

    p1, p2, match = str:find("^pets? *(%a*)$")
    if p1 then
        match = match:lower()
        if match == 'on' then
            setPets(true)
        elseif match == 'off' then
            setPets(false)
        else
            setPets(nil)
        end
        return
    end

    -----

    local function setTalents(tf)
        tf = tf or not IronmanUserData.AllowTalents
        if tf then
            if IronmanUserData.AllowMaps then
                ns:warn(L.err_disable_maps("/iron maps"))
                return
            end
            if IronmanUserData.AllowPets then
                ns:warn(L.err_disable_pets("/iron pets"))
                return
            end
        else
            if ns:playerHasTalents() then
                ns:warn(L.err_cannot_disable_talents)
                return
            end
        end

        IronmanUserData.AllowTalents = tf

        ns:success(IronmanUserData.AllowTalents and L.talents_on or L.talents_off)
        ns:success(L.description())
        ns:checkTalents()
        print(" ")
    end

    p1, p2, match = str:find("^talents? *(%a*)$")
    if p1 then
        match = match:lower()
        if match == 'on' then
            setTalents(true)
        elseif match == 'off' then
            setTalents(false)
        else
            setTalents(nil)
        end
        return
    end

    -----

    local function currentlyOnOrOff(tf)
        return " (" .. (tf and L.currently_on or L.currently_off) .. ")"
    end

    print(' ')
    print(ns:colorText('ff8000', L.title))
    print(ns:colorCmd("/iron {N}") .. " - " .. L.cmdln_n .. L.currently_n(IronmanUserData.Interval))
    print(ns:colorCmd("/iron on/off") .. " - " .. L.cmdln_on_off .. currentlyOnOrOff(not IronmanUserData.Suppress))
    print(' ')
    print(ns:colorText('ff8000', L.optional_rules))
    print(ns:colorCmd("/iron maps [on/off]") .. " - " .. L.cmdln_maps .. currentlyOnOrOff(IronmanUserData.AllowMaps))
    print(ns:colorCmd("/iron pets [on/off]") .. " - " .. L.cmdln_pets .. currentlyOnOrOff(IronmanUserData.AllowPets))
    print(ns:colorCmd("/iron talents [on/off]") .. " - " .. L.cmdln_talents .. currentlyOnOrOff(IronmanUserData.AllowTalents))
    print(' ')
end

--[[
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@                                                                              @@
@@  Main addon functions                                                        @@
@@                                                                              @@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
]]

function ns:init()
    ns:initDB()
    initMaps()

    adapter:after(2, function()
        ns:success(L.description())
        if IronmanUserData.Suppress then
            ns:success(L.checking_off_s('/iron on'))
        end
        ns:success(L.type_s_for_more_info('/iron'))
        _initialized = true
        ns:checkAll()
    end)
end

function ns:died()
    IronmanUserData.DeathCount = IronmanUserData.DeathCount + 1
    ns:checkAll()
end

function ns:initDB(force)
    if force or not IronmanUserData then
        IronmanUserData = {}
    end
    if IronmanUserData.DeathCount    == nil then IronmanUserData.DeathCount    = 0     end
    if IronmanUserData.Interval      == nil then IronmanUserData.Interval      = 15    end
    if IronmanUserData.Suppress      == nil then IronmanUserData.Suppress      = false end
    if IronmanUserData.AllowPets     == nil then IronmanUserData.AllowPets     = false end
    if IronmanUserData.AllowMaps     == nil then IronmanUserData.AllowMaps     = false end
    if IronmanUserData.AllowTalents  == nil then IronmanUserData.AllowTalents  = false end
end

function ns:playSound(path)
    if not _initialized then return end
    adapter:playSound(path)
end

function ns:colorText(hex6, text)
    return "|cFF" .. hex6 .. text .. "|r"
end

function ns:colorCmd(text)
    return ns:colorText('ffd000', text)
end

function ns:info(text)
    print(ns:colorText('c0c0c0', L.prefix) .. ns:colorText('ffffff', text))
end

function ns:warn(text, flash, sound)
    print(ns:colorText('ff0000', L.prefix) .. ns:colorText('ffffff', text))
    if type(flash) == "string" then
        ns:flash(flash)
    elseif flash then
        ns:flash(text)
    end
    if type(sound) == "string" then
        ns:playSound(sound)
    elseif sound then
        ns:playSound(ERROR_SOUND_FILE)
    end
end

function ns:success(text)
    print(ns:colorText('0080ff', L.prefix) .. ns:colorText('00ff00', text))
end

function ns:flash(text)
    UIErrorsFrame:AddMessage(text, 1.0, 0.5, 0.0, GetChatTypeIndex('SYSTEM'), 8);
end

function ns:playerHasTalents()
    for i = 1, GetNumTalentTabs() do
        local _,_,_,_,points = GetTalentTabInfo(i)
        if points and points > 0 then
            return true
        end
    end
    return false
end

function ns:checkAllDelayed(nSeconds)
    if _waitingToCheckAll then return end
    _waitingToCheckAll = true
    nSeconds = nSeconds or 0.5
    adapter:after(nSeconds, ns.checkAll)
end

function ns:checkAll()
    if not _initialized then return end
    if IronmanUserData.Suppress then return end
    local n = 0
    n = n + ns:checkDeath()
    n = n + ns:checkGear()
    n = n + ns:checkInventory()
    n = n + ns:checkTalents()
    n = n + ns:checkProfessions()
    n = n + ns:checkPets()
    n = n + ns:checkBuffs()
    n = n + ns:checkAddons()
    if n > 0 then
        if n > 1 then print(' ') end
        if _lastErrorCount == 0 then
            ns:playSound(ERROR_SOUND_FILE)
        end
    end
    _lastErrorCount = n
    _secondsSinceLastUpdate = 0
    _waitingToCheckAll = false
end

function ns:checkDeath()
    local count = 0
    if IronmanUserData and IronmanUserData.DeathCount and IronmanUserData.DeathCount >= 0 then
        count = IronmanUserData.DeathCount
    end
    if count > 0 then
        ns:warn(L.err_you_died)
    end
    return (count > 0 and 1 or 0)
end

function ns:checkGear()
    local errorcount = 0
    for slotkey, slotname in pairs(L.SLOTS) do
        local id = GetInventorySlotInfo(slotkey:upper()..'SLOT')
        local quality = GetInventoryItemQuality("player", id)
        local link = GetInventoryItemLink("player", id)
        if quality and quality > 1 then
            errorcount = errorcount + 1
            ns:warn(L.err_unequip_s_s(slotname, link))
        elseif link then
            local _, enchantId = link:match("item:(%d+):(%d+)")
            if enchantId and enchantId ~= "0" then
                errorcount = errorcount + 1
                ns:warn(L.err_unequip_enchanted_s_s(slotname, link))
            end
        end
    end
    return errorcount
end

function ns:checkInventory()
    local errorcount = 0
    local foundLinks = {}
    for bagIndex = 0, (NUM_BAG_SLOTS or 4) do
        local numSlots = adapter:getContainerNumSlots(bagIndex)
        if numSlots and numSlots > 0 then
            for slotIndex = 1, numSlots do
                local itemLink = adapter:getContainerItemLink(bagIndex, slotIndex)
                if itemLink then
                    local itemId = tonumber(itemLink:match("item:(%d+)"))
                    if itemId and FORBIDDEN_ITEMS[itemId] then
                        foundLinks[itemId] = itemLink
                    end
                end
            end
        end
    end
    for _, link in pairs(foundLinks) do
        ns:warn(L.err_you_cannot_use_s(link))
        errorcount = errorcount + 1
    end
    return errorcount
end

function ns:checkTalents()
    if not IronmanUserData.AllowTalents then
        if ns:playerHasTalents() then
            ns:warn(L.err_reset_talents)
            return 1
        end
    end
    return 0
end

function ns:checkProfessions()
    local nPrimary, nSecondary = adapter:getNumProfessions()
    if nPrimary > 0 then
        ns:warn(L.err_unlearn_n_profs(nPrimary))
        return nPrimary
    end
    return 0
end

function ns:checkPets()
    if UnitExists("pet") and not IronmanUserData.AllowPets then
        ns:warn(L.err_pet)
        return 1
    end
    return 0
end

function ns:checkBuffs()
    local errorcount = 0
    local buffs = adapter:getBuffs('player')
    for name, buff in pairs(buffs) do
        local isSelf = (buff.caster and (buff.caster == "player" or buff.caster == "pet"))
        if not isSelf then
            errorcount = errorcount + 1
            ns:warn(L.err_buff_external(name))
        elseif L.SCROLL_BUFFS[name] then
            errorcount = errorcount + 1
            ns:warn(L.err_buff_disallowed(name))
        end
    end
    return errorcount
end

function ns:checkAddons()
    -- We only perform this check 1 in 10 times.
    _checkAddonsCount = _checkAddonsCount + 1
    if _checkAddonsCount % 10 ~= 1 then return 0 end

    local errorcount = 0

    if IsAddOnLoaded("Questie") or _G.Questie then
        errorcount = errorcount + 1
        ns:warn(L.err_unload_addon("Questie"))
    end
    if IsAddOnLoaded("Leatrix_Maps") or _G.LeatrixMaps then
        errorcount = errorcount + 1
        ns:warn(L.err_unload_addon("Leatrix Maps"))
    end
    if IsAddOnLoaded("Leatrix_Sounds") or _G.LeatrixSounds then
        errorcount = errorcount + 1
        ns:warn(L.err_unload_addon("Leatrix Sounds"))
    end
    if IsAddOnLoaded("ZygorGuidesViewer") or _G.ZygorGuidesViewer then
        errorcount = errorcount + 1
        ns:warn(L.err_unload_addon("Zygor Guides"))
    end
    if IsAddOnLoaded("RestedXP") or _G.RXPData or _G.RXPGuides then
        errorcount = errorcount + 1
        ns:warn(L.err_unload_addon("RestedXP"))
    end
    if IsAddOnLoaded("RXPGuides") or _G.RXPGuides then
        errorcount = errorcount + 1
        ns:warn(L.err_unload_addon("RXPGuides"))
    end
    if IsAddOnLoaded("ElvUI") or _G.ElvUI then
        errorcount = errorcount + 1
        ns:warn(L.err_unload_addon("ElvUI"))
    end
    if IsAddOnLoaded("WeakAuras") or _G.WeakAuras then
        errorcount = errorcount + 1
        ns:warn(L.err_unload_addon("WeakAuras"))
    end
    if IsAddOnLoaded("DBM-Core") or IsAddOnLoaded("DBM-Classic") or _G.DBM then
        errorcount = errorcount + 1
        ns:warn(L.err_unload_addon("Deadly Boss Mods"))
    end
    if IsAddOnLoaded("BigWigs") or IsAddOnLoaded("BigWigs_Classic") or _G.BigWigs then
        errorcount = errorcount + 1
        ns:warn(L.err_unload_addon("BigWigs"))
    end
    if IsAddOnLoaded("TidyPlates_ThreatPlates") or _G.ThreatPlates then
        errorcount = errorcount + 1
        ns:warn(L.err_unload_addon("Threat Plates"))
    end
    if IsAddOnLoaded("Plater") or _G.Plater then
        errorcount = errorcount + 1
        ns:warn(L.err_unload_addon("Plater Nameplates"))
    end
    if IsAddOnLoaded("Kui_Nameplates") or _G.KuiNameplatesCore then
        errorcount = errorcount + 1
        ns:warn(L.err_unload_addon("KuiNameplates"))
    end
    if IsAddOnLoaded("ShadowedUnitFrames") or _G.ShadowUF or _G.ShadowedUF then
        errorcount = errorcount + 1
        ns:warn(L.err_unload_addon("Shadowed Unit Frames"))
    end
    if IsAddOnLoaded("ZPerl") or IsAddOnLoaded("XPerl") or _G.ZPerl or _G.XPerl then
        errorcount = errorcount + 1
        ns:warn(L.err_unload_addon("ZPerl/XPerl"))
    end
    if IsAddOnLoaded("LunaUnitFrames") or _G.LunaUnitFrames then
        errorcount = errorcount + 1
        ns:warn(L.err_unload_addon("Luna Unit Frames"))
    end
    if IsAddOnLoaded("Grid2") or _G.Grid2 then
        errorcount = errorcount + 1
        ns:warn(L.err_unload_addon("Grid2"))
    end
    if IsAddOnLoaded("VuhDo") or _G.VUHDO_GLOBAL or _G.VuhDo then
        errorcount = errorcount + 1
        ns:warn(L.err_unload_addon("VuhDo"))
    end
    if IsAddOnLoaded("HealBot") or _G.HealBot then
        errorcount = errorcount + 1
        ns:warn(L.err_unload_addon("HealBot"))
    end
    if IsAddOnLoaded("Clique") or _G.Clique then
        errorcount = errorcount + 1
        ns:warn(L.err_unload_addon("Clique"))
    end
    if IsAddOnLoaded("ClassicCastbars") or _G.ClassicCastbars then
        errorcount = errorcount + 1
        ns:warn(L.err_unload_addon("ClassicCastbars"))
    end
    if IsAddOnLoaded("ClassicAuraDurations") or _G.ClassicAuraDurations then
        errorcount = errorcount + 1
        ns:warn(L.err_unload_addon("Classic Aura Durations"))
    end
    if IsAddOnLoaded("RealMobHealth") or _G.RealMobHealth then
        errorcount = errorcount + 1
        ns:warn(L.err_unload_addon("RealMobHealth"))
    end
    if IsAddOnLoaded("TomTom") or _G.TomTom then
        errorcount = errorcount + 1
        ns:warn(L.err_unload_addon("TomTom"))
    end
    if IsAddOnLoaded("NovaWorldBuffs") or _G.NWB then
        errorcount = errorcount + 1
        ns:warn(L.err_unload_addon("NovaWorldBuffs"))
    end
    if IsAddOnLoaded("NovaRaidCompanion") or _G.NRC then
        errorcount = errorcount + 1
        ns:warn(L.err_unload_addon("NovaRaidCompanion"))
    end
    if IsAddOnLoaded("RCLootCouncil_Classic") or _G.RCLootCouncil then
        errorcount = errorcount + 1
        ns:warn(L.err_unload_addon("RCLootCouncil Classic"))
    end
    if IsAddOnLoaded("ThreatClassic2") or _G.ThreatClassic2 or _G.tc2 then
        errorcount = errorcount + 1
        ns:warn(L.err_unload_addon("ThreatClassic2"))
    end
    if IsAddOnLoaded("WeaponSwingTimer") or _G.WeaponSwingTimer then
        errorcount = errorcount + 1
        ns:warn(L.err_unload_addon("WeaponSwingTimer"))
    end
    if IsAddOnLoaded("ClassicSwingTimer") or _G.ClassicSwingTimer then
        errorcount = errorcount + 1
        ns:warn(L.err_unload_addon("Classic Swing Timer"))
    end
    if IsAddOnLoaded("Postal") or _G.Postal then
        errorcount = errorcount + 1
        ns:warn(L.err_unload_addon("Postal"))
    end
    if IsAddOnLoaded("Pawn") or _G.Pawn then
        errorcount = errorcount + 1
        ns:warn(L.err_unload_addon("Pawn"))
    end

    if errorcount > 0 then
        ns:warn(L.qol_addons_ok)
    end
    return errorcount
end
