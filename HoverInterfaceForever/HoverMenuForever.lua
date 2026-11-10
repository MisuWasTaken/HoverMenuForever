local addonName = ...

local defaults = {
    hideMenu = true, hideBags = true, hideQuests = true, hideMinimap = true,
    menuDelay = 4, bagsDelay = 4, questsDelay = 4, minimapDelay = 4,
    fadeDuration = 0.3,
}

local db, settingsCategory, backpackButton
local initialized, scanTimer, visibilityTimer = false, 0, 0
local VISIBILITY_INTERVAL = 1 / 30
local SCAN_INTERVAL = 2
local sexyMapLoaded, CheckSexyMap = false, nil
local minimapHiddenByUs = {}
local cachedMinimapBounds

local groups = {
    menu = { names = {"MicroMenu", "MicroMenuContainer"}, hide = "hideMenu", delay = "menuDelay", alpha = 0, lastHover = -100000 },
    bags = { names = {"BagsBar", "MainMenuBarBagManager"}, hide = "hideBags", delay = "bagsDelay", alpha = 0, lastHover = -100000 },
    quests = { names = {"Questie_BaseFrame", "ObjectiveTrackerFrame"}, hide = "hideQuests", delay = "questsDelay", alpha = 0, lastHover = -100000 },
    minimap = { names = {"MinimapCluster", "Minimap"}, hide = "hideMinimap", delay = "minimapDelay", alpha = 0, lastHover = -100000 },
}

local bagSlots = {}
local bagSlotNames = {
    "CharacterBag0Slot", "CharacterBag1Slot", "CharacterBag2Slot", "CharacterBag3Slot",
    "CharacterBag4Slot", "CharacterReagentBag0Slot", "BagBarExpandToggle", "KeyRingButton",
}
local events = CreateFrame("Frame")

local function SetAlphaSafe(region, value)
    if not region or not region.SetAlpha then return end
    local ok, current = pcall(region.GetAlpha, region)
    if ok and type(current) == "number" and math.abs(current - value) < 0.005 then return end
    pcall(region.SetAlpha, region, value)
end

local function TrackBagSlot(frame)
    if not frame or frame == backpackButton or not frame.SetAlpha then return end
    bagSlots[frame] = true
end

local function ScanBagSlots()
    for _, name in ipairs(bagSlotNames) do TrackBagSlot(_G[name]) end

    local manager = _G.MainMenuBarBagManager
    if manager and manager.EnumerateBagButtons then
        pcall(function()
            for _, button in manager:EnumerateBagButtons() do TrackBagSlot(button) end
        end)
    end

    local bags = groups.bags.frame
    if bags and bags.GetChildren then
        for _, child in ipairs({bags:GetChildren()}) do
            if child.IsObjectType and child:IsObjectType("Button") then TrackBagSlot(child) end
        end
    end
end

local function ScanFrames()
    backpackButton = _G.MainMenuBarBackpackButton or backpackButton
    sexyMapLoaded = CheckSexyMap()

    for key, group in pairs(groups) do
        if not group.frame then
            for _, name in ipairs(group.names) do
                local frame = _G[name]
                if frame and frame.IsShown and frame.SetAlpha then
                    group.frame = frame
                    break
                end
            end
        end

    end

    if _G.Questie_BaseFrame then groups.quests.frame = _G.Questie_BaseFrame end
    ScanBagSlots()
end

local function IsInFrame(frame)
    if not frame or not frame.IsShown or not frame:IsShown() then return false end

    if GetCursorPosition and frame.GetLeft and frame.GetEffectiveScale then
        local ok, inside = pcall(function()
            local left, right, bottom, top = frame:GetLeft(), frame:GetRight(), frame:GetBottom(), frame:GetTop()
            local scale = frame:GetEffectiveScale()
            if not left or not right or not bottom or not top or not scale or scale <= 0 then return false end
            local x, y = GetCursorPosition()
            x, y = x / scale, y / scale
            return x >= left and x <= right and y >= bottom and y <= top
        end)
        if ok and inside then return true end
    end

    local ok, hovered = pcall(frame.IsMouseOver, frame)
    return ok and hovered or false
end

local function IsDescendantOf(frame, ancestor)
    if not frame or not ancestor then return false end
    local checks = 0
    while frame and checks < 30 do
        if frame == ancestor then return true end
        if not frame.GetParent then return false end
        frame = frame:GetParent()
        checks = checks + 1
    end
    return false
end

CheckSexyMap = function()
    if C_AddOns and C_AddOns.IsAddOnLoaded then
        local ok, loaded = pcall(C_AddOns.IsAddOnLoaded, "SexyMap")
        if ok then return loaded == true end
    end
    if IsAddOnLoaded then
        local ok, loaded = pcall(IsAddOnLoaded, "SexyMap")
        if ok then return loaded == true end
    end
    return false
end

local function CursorInMinimap(frame, margin)
    if not frame or not GetCursorPosition then return false end
    local ok, left, right, bottom, top, scale = pcall(function()
        return frame:GetLeft(), frame:GetRight(), frame:GetBottom(), frame:GetTop(), frame:GetEffectiveScale()
    end)
    if ok and left and right and bottom and top and scale and scale > 0 then
        if not cachedMinimapBounds then cachedMinimapBounds = {} end
        local b = cachedMinimapBounds
        b[1], b[2], b[3], b[4], b[5] = left, right, bottom, top, scale
    end
    local b = cachedMinimapBounds
    if not b then return false end
    local x, y = GetCursorPosition()
    x, y = x / b[5], y / b[5]
    return x >= b[1] - margin and x <= b[2] + margin
        and y >= b[3] - margin and y <= b[4] + margin
end

local function MouseInMinimap()
    local minimap, cluster = _G.Minimap, _G.MinimapCluster
    if minimap and CursorInMinimap(minimap, sexyMapLoaded and 40 or 25) then return true end
    if not sexyMapLoaded and cluster and IsInFrame(cluster) then return true end
    return false
end

local function ApplyMinimapFrame(frame, alpha, hideAtZero)
    if not frame then return end

    if not hideAtZero and minimapHiddenByUs[frame] then
        local ok = pcall(frame.Show, frame)
        if ok then minimapHiddenByUs[frame] = nil end
    end

    SetAlphaSafe(frame, alpha)

    if hideAtZero and frame.IsShown and frame:IsShown() then
        local ok = pcall(frame.Hide, frame)
        if ok then minimapHiddenByUs[frame] = true end
    end
end

local function FadeMinimap(alpha)
    local minimap, cluster, backdrop = _G.Minimap, _G.MinimapCluster, _G.MinimapBackdrop
    local hideAtZero = db and db.hideMinimap and alpha <= 0.001 and not ((SettingsPanel and SettingsPanel:IsShown()) or (EditModeManagerFrame and EditModeManagerFrame:IsShown()))

    ApplyMinimapFrame(cluster, alpha, hideAtZero)
    if minimap and minimap ~= cluster then
        local inherited = cluster and IsDescendantOf(minimap, cluster)
        ApplyMinimapFrame(minimap, inherited and 1 or alpha, hideAtZero)
    end
    if backdrop and not IsDescendantOf(backdrop, minimap) and not IsDescendantOf(backdrop, cluster) then
        ApplyMinimapFrame(backdrop, alpha, hideAtZero)
    end
end

local function MouseInBags()
    if IsInFrame(groups.bags.frame) or IsInFrame(_G.MainMenuBarBagManager) or IsInFrame(backpackButton) then
        return true
    end
    for button in pairs(bagSlots) do
        if IsInFrame(button) then return true end
    end
    return false
end

local function SettingsOrEditMode()
    return (SettingsPanel and SettingsPanel:IsShown()) or (EditModeManagerFrame and EditModeManagerFrame:IsShown())
end

local function Smooth(current, target, delta, seconds)
    if seconds <= 0 then return target end
    local amount = delta / seconds
    if current < target then return math.min(target, current + amount) end
    if current > target then return math.max(target, current - amount) end
    return current
end

local function UpdateVisibility(delta)
    if not db then return end
    local now, editing = GetTime(), SettingsOrEditMode()

    for _, group in pairs(groups) do
        if group.frame or (group == groups.bags and backpackButton) then
            local mouseOver = group == groups.bags and MouseInBags()
                or group == groups.minimap and MouseInMinimap()
                or (group ~= groups.bags and group ~= groups.minimap and IsInFrame(group.frame))
            if mouseOver then group.lastHover = now end
            local visible = editing or not db[group.hide] or (now - group.lastHover <= db[group.delay])
            group.alpha = Smooth(group.alpha, visible and 1 or 0, delta, db.fadeDuration)
        end
    end

    SetAlphaSafe(groups.menu.frame, groups.menu.alpha)
    SetAlphaSafe(groups.quests.frame, groups.quests.alpha)
    FadeMinimap(groups.minimap.alpha)

    local bags = groups.bags.frame
    local manager = _G.MainMenuBarBagManager
    local bagsAlpha = groups.bags.alpha

    local fadeBags, fadeManager = bags ~= nil, manager ~= nil and manager ~= bags
    if fadeBags and fadeManager then
        if IsDescendantOf(bags, manager) then
            fadeBags = false
        elseif IsDescendantOf(manager, bags) then
            fadeManager = false
        end
    end

    if bags then SetAlphaSafe(bags, fadeBags and bagsAlpha or 1) end
    if manager and manager ~= bags then SetAlphaSafe(manager, fadeManager and bagsAlpha or 1) end

    if backpackButton then
        local inside = (fadeBags and IsDescendantOf(backpackButton, bags))
            or ((fadeManager or manager == bags) and IsDescendantOf(backpackButton, manager))
        SetAlphaSafe(backpackButton, inside and 1 or bagsAlpha)
    end
    for button in pairs(bagSlots) do
        local inside = (fadeBags and IsDescendantOf(button, bags))
            or ((fadeManager or manager == bags) and IsDescendantOf(button, manager))
        SetAlphaSafe(button, inside and 1 or bagsAlpha)
    end
end

local function RegisterSettings()
    if not Settings or not Settings.RegisterVerticalLayoutCategory then return end
    local category, layout = Settings.RegisterVerticalLayoutCategory("HoverMenu Forever")
    settingsCategory = category

    local function Section(title)
        if layout and CreateSettingsListSectionHeaderInitializer then
            layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(title))
        end
    end

    local function OnChanged()
        UpdateVisibility(0)
    end

    local function Checkbox(key, title, description)
        local setting = Settings.RegisterAddOnSetting(category, addonName .. "_" .. key, key, db, "boolean", title, defaults[key])
        Settings.CreateCheckbox(category, setting, description)
        setting:SetValueChangedCallback(OnChanged)
    end

    local function Slider(key, title, description, minimum, maximum, step, decimal)
        local setting = Settings.RegisterAddOnSetting(category, addonName .. "_" .. key, key, db, "number", title, defaults[key])
        local options = Settings.CreateSliderOptions(minimum, maximum, step)
        options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(value)
            if decimal then return string.format("%.1f s", value) end
            return string.format("%d s", math.floor(value + 0.5))
        end)
        Settings.CreateSlider(category, setting, options, description)
        setting:SetValueChangedCallback(OnChanged)
    end

    Section("Game menu")
    Checkbox("hideMenu", "Fade game menu", "Shows character, talents, quest log, map and menu buttons on mouseover.")
    Slider("menuDelay", "Hide delay", "Seconds the game menu stays visible after moving the mouse away.", 0, 15, 1)

    Section("Bags")
    Checkbox("hideBags", "Fade bag bar", "Shows all bag buttons, including the main backpack, together on mouseover.")
    Slider("bagsDelay", "Hide delay", "Seconds the bag bar stays visible after moving the mouse away.", 0, 15, 1)

    Section("Quest tracker (Questie & Blizzard)")
    Checkbox("hideQuests", "Fade quest tracker", "Supports Questie and the default Blizzard objective tracker.")
    Slider("questsDelay", "Hide delay", "Seconds the quest tracker stays visible after moving the mouse away.", 0, 15, 1)

    Section("Minimap")
    Checkbox("hideMinimap", "Fade minimap", "Supports SexyMap borders and effects. Does not affect the world map.")
    Slider("minimapDelay", "Hide delay", "Seconds the minimap stays visible after moving the mouse away.", 0, 15, 1)

    Section("Animation")
    Slider("fadeDuration", "Fade duration", "Time to fade in or out. Set to 0 s for an instant transition.", 0, 1.5, 0.1, true)

    Settings.RegisterAddOnCategory(category)
end

local function OpenSettings()
    if settingsCategory and Settings and Settings.OpenToCategory then
        Settings.OpenToCategory(settingsCategory:GetID())
    else
        print("|cff80ff80HoverMenu:|r Opciones > AddOns > HoverMenu Forever")
    end
end

SLASH_HOVERMENUFOREVER1, SLASH_HOVERMENUFOREVER2 = "/hovermenu", "/hmf"
SlashCmdList.HOVERMENUFOREVER = function(message)
    message = (message or ""):lower():match("^%s*(.-)%s*$")
    if message == "debug" then
        ScanFrames()
        print("HoverMenu Forever 0.5.2 - diagnostics:")
        for key, group in pairs(groups) do
            print(key .. ": " .. (group.frame and (group.frame:GetName() or "unnamed") or "not found"))
        end
        local count = 0
        for _ in pairs(bagSlots) do count = count + 1 end
        print("Backpack: " .. (backpackButton and "OK" or "not found") .. "; bag buttons found: " .. count)
        local mm, cluster = _G.Minimap, _G.MinimapCluster
        print("SexyMap: " .. (sexyMapLoaded and "detected" or "not detected")
            .. "; Minimap: " .. (mm and "OK" or "not found")
            .. "; MinimapCluster: " .. (cluster and "OK" or "not found"))
        if mm and cluster then
            print("Minimap inside Cluster: " .. (IsDescendantOf(mm, cluster) and "yes" or "no"))
        end
        return
    end
    OpenSettings()
end

events:SetScript("OnEvent", function(self, event, name)
    if event == "ADDON_LOADED" and name == addonName then
        HoverMenuForeverDB = HoverMenuForeverDB or {}
        db = HoverMenuForeverDB

        local oldDelay = tonumber(db.delay)
        if oldDelay then
            for _, key in ipairs({"menuDelay", "bagsDelay", "questsDelay", "minimapDelay"}) do
                if db[key] == nil then db[key] = math.max(0, math.min(15, oldDelay)) end
            end
            db.delay = nil
        end
        for key, value in pairs(defaults) do
            if db[key] == nil then db[key] = value end
        end
        for _, key in ipairs({"menuDelay", "bagsDelay", "questsDelay", "minimapDelay"}) do
            db[key] = math.max(0, math.min(15, tonumber(db[key]) or defaults[key]))
        end
        db.fadeDuration = math.max(0, math.min(1.5, tonumber(db.fadeDuration) or defaults.fadeDuration))
        db.keepBackpack = nil
        db.showBagSlots = nil
        db.showFreeSlots = nil
        RegisterSettings()

    elseif event == "PLAYER_LOGIN" then
        initialized = true
        ScanFrames()
        UpdateVisibility(0)
    end
end)

events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_ENTERING_WORLD")

events:SetScript("OnUpdate", function(self, elapsed)
    if not initialized then return end
    scanTimer = scanTimer + elapsed
    if scanTimer >= SCAN_INTERVAL then
        scanTimer = scanTimer % SCAN_INTERVAL
        ScanFrames()
    end

    visibilityTimer = visibilityTimer + elapsed
    if visibilityTimer < VISIBILITY_INTERVAL then return end
    local delta = visibilityTimer
    visibilityTimer = 0
    UpdateVisibility(delta)
end)
