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
@@  Events                                                                      @@
@@                                                                              @@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
]]

local eventFrame = CreateFrame('frame', ADDONNAME .. "_Events")

eventFrame:SetScript('OnUpdate', function(self, elapsed)
    if not _initialized then return end
    _secondsSinceLastUpdate = _secondsSinceLastUpdate + elapsed
    if _secondsSinceLastUpdate > IronmanUserData.Interval then
        ns:checkAll()
        _secondsSinceLastUpdate = 0
    end
end)

eventFrame:RegisterEvent("PLAYER_LOGIN");
eventFrame:RegisterEvent("PLAYER_DEAD");
eventFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED");
eventFrame:RegisterEvent("BAG_UPDATE_DELAYED");
eventFrame:RegisterEvent("UNIT_AURA")
eventFrame:RegisterEvent("UNIT_PET")
eventFrame:RegisterEvent("MAIL_SHOW")
eventFrame:RegisterEvent("AUCTION_HOUSE_SHOW")
eventFrame:RegisterEvent("LEARNED_SPELL_IN_TAB")

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == 'PLAYER_LOGIN' then
        ns:init()
    elseif event == 'PLAYER_DEAD' then
        ns:died()
    elseif event == 'BAG_UPDATE_DELAYED' then
        ns:checkAllDelayed()
    elseif event == "UNIT_AURA" then
        ns:checkAllDelayed()
    elseif event == "UNIT_PET" then
        ns:checkAllDelayed()
    elseif event == "MAIL_SHOW" then
        ns:playSound(ERROR_SOUND_FILE)
        ns:flash(L.err_no_mail)
        ns:fail(L.err_no_mail)
    elseif event == "AUCTION_HOUSE_SHOW" then
        ns:playSound(ERROR_SOUND_FILE)
        ns:flash(L.err_no_ah)
        ns:fail(L.err_no_ah)
    elseif event == "LEARNED_SPELL_IN_TAB" then
        ns:checkAllDelayed()
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
            ns:fail(L.err_seconds_ij(15, 300))
            return
        end
        IronmanUserData.Interval = n
        ns:success(L.checking_every_n(n))
        return
    end

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

    local function setPets(tf)
        if tf == nil then
            IronmanUserData.AllowPets = not IronmanUserData.AllowPets
        else
            IronmanUserData.AllowPets = tf
        end
        ns:success(IronmanUserData.AllowPets and L.pets_on or L.pets_off)
        ns:checkPets()
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

    local color = 'ffd000'

    local function currentlyOnOrOff(tf)
        return " (" .. (tf and L.currently_on or L.currently_off) .. ")"
    end

    print(' ')
    print(ns:colorText('ff8000', L.title))
    print(L.description)
    print(' ')
    print(ns:colorText(color, "/iron {N}")  .. " - " .. L.cmdln_n)
    print(ns:colorText(color, "/iron on/off")  .. " - " .. L.cmdln_on_off .. currentlyOnOrOff(not IronmanUserData.Suppress))
    print(ns:colorText(color, "/iron pet [on/off]")  .. " - " .. L.cmdln_pets .. currentlyOnOrOff(IronmanUserData.AllowPets))
    print(' ')
    print(L.disclaimer)
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
    adapter:after(2, function()
        if IronmanUserData.Suppress then
            ns:success(L.init_checking_off_s(ns:colorText('ffd000', '/iron on')))
        else
            ns:success(L.init_checking_on_n(IronmanUserData.Interval))
        end
        ns:success(L.type_s_for_more_info(ns:colorText('ffd000', '/iron')))
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
    if IronmanUserData.DeathCount == nil then IronmanUserData.DeathCount = 0     end
    if IronmanUserData.Interval   == nil then IronmanUserData.Interval   = 15    end
    if IronmanUserData.Suppress   == nil then IronmanUserData.Suppress   = false end
    if IronmanUserData.AllowPets  == nil then IronmanUserData.AllowPets  = false end
end

function ns:playSound(path)
    if not _initialized then return end
    adapter:playSound(path)
end

function ns:colorText(hex6, text)
    return "|cFF" .. hex6 .. text .. "|r"
end

function ns:info(text)
    print(ns:colorText('c0c0c0', L.prefix) .. ns:colorText('ffffff', text))
end

function ns:fail(text)
    print(ns:colorText('ff0000', L.prefix) .. ns:colorText('ffffff', text))
end

function ns:success(text)
    print(ns:colorText('0080ff', L.prefix) .. ns:colorText('00ff00', text))
end

function ns:flash(text)
    UIErrorsFrame:AddMessage(text, 1.0, 0.5, 0.0, GetChatTypeIndex('SYSTEM'), 8);
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
        ns:fail(L.err_you_died)
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
            ns:fail(L.err_unequip_s_s(slotname, link))
        elseif link then
            local _, enchantId = link:match("item:(%d+):(%d+)")
            if enchantId and enchantId ~= "0" then
                errorcount = errorcount + 1
                ns:fail(L.err_unequip_enchanted_s_s(slotname, link))
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
        ns:fail(L.err_you_cannot_use_s(link))
        errorcount = errorcount + 1
    end
    return errorcount
end

function ns:checkTalents()
    for i = 1, GetNumTalentTabs() do
        local _,_,_,_,points = GetTalentTabInfo(i)                              
        if points and points > 0 then
            ns:fail(L.err_reset_talents)
            return 1
        end
    end
    return 0
end

function ns:checkProfessions()
    local nPrimary, nSecondary = adapter:getNumProfessions()
    if nPrimary > 0 then
        ns:fail(L.err_unlearn_n_profs(nPrimary))
        return nPrimary
    end
    return 0
end

function ns:checkPets()
    if UnitExists("pet") and not IronmanUserData.AllowPets then
        ns:fail(L.err_pet)
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
            ns:fail(L.err_buff_external(name))
        elseif L.SCROLL_BUFFS[name] then
            errorcount = errorcount + 1
            ns:fail(L.err_buff_disallowed(name))
        end
    end
    return errorcount
end
