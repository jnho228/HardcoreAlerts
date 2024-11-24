--[[ 
Hardcore Death Alerts Addon v1.0.0
- Tracks and displays deaths in Hardcore realms.

Quick Setup:
1. Enable Hardcore Death Announcements and set them to ALL DEATHS. (Hardcore Death Alerts can be 'never' and it still works fine.)
2. Join the 'HardcoreDeaths' channel. You can hide this channel in your chat settings.
3. Use /hcalerts for commands.

Commands:
/hcalerts reset    - Clears the death log.
/hcalerts show     - Shows the death tracker window.
/hcalerts hide     - Hides the death tracker window.

Enjoy tracking the inevitable!
--]]

-- Localize frequently used globals for faster access
local CreateFrame = CreateFrame
local string = string
local table = table
local PlaySound = PlaySound
local UnitLevel = UnitLevel
local pairs = pairs
local tonumber = tonumber
local match = string.match
local format = string.format
local insert = table.insert
local remove = table.remove

-- Namespace with local cache
local HCA = {
    deathData = {},
    frameCache = {},
    colorCache = {},
    patterns = {
        {"fell to their death", "Falling"}, -- Falling
        {"died of fatigue", "Fatigue"},     -- Fatigue
        {"drowned to death", "Drowned"},    -- Drowned
        {"has been slain by a (.+)", nil},  -- Monster Death
        {"has been slain by (.+)", nil}     -- Player / Duel Death
    }
}

-- Initialize saved variables
HardcoreAlertsDB = HardcoreAlertsDB or {}
HCA.deathData = HardcoreAlertsDB

-- Cache frequently used colors
local COLOR_CACHE = {
    [-6] = "|cff808080", -- gray
    [-5] = "|cff00ff00", -- green
    [-2] = "|cffffff00", -- yellow
    [0] = "|cffffff00",  -- yellow
    [3] = "|cffff7f00",  -- orange
    [5] = "|cffff0000"   -- red
}

-- Optimized color calculation
local function GetLevelColor(deathLevel)
    local levelDiff = deathLevel - UnitLevel("player")
    local color
    
    if levelDiff >= 5 then
        color = COLOR_CACHE[5]
        return color, true
    elseif levelDiff >= 3 then
        color = COLOR_CACHE[3]
        return color, true
    elseif levelDiff >= 0 then
        color = COLOR_CACHE[0]
        return color, true
    elseif levelDiff >= -2 then
        color = COLOR_CACHE[-2]
        return color, false
    elseif levelDiff >= -5 then
        color = COLOR_CACHE[-5]
        return color, false
    else
        color = COLOR_CACHE[-6]
        return color, false
    end
end

-- Create UI elements (moved to a separate function for cleaner initialization)
local function InitializeUI()
    -- Main frame
    local addonFrame = CreateFrame("Frame", "DeathTrackerFrame", UIParent, "BackdropTemplate")
    addonFrame:SetSize(200, 300)
    addonFrame:SetPoint("CENTER")
    addonFrame:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 }
    })
    addonFrame:SetBackdropColor(0, 0, 0, 0.8)
    addonFrame:EnableMouse(true)
    addonFrame:SetMovable(true)
    addonFrame:RegisterForDrag("LeftButton")
    addonFrame:SetScript("OnDragStart", addonFrame.StartMoving)
    addonFrame:SetScript("OnDragStop", addonFrame.StopMovingOrSizing)
    addonFrame:SetResizable(true)
    addonFrame:SetResizeBounds(150, 200, 400, 600)

    -- Resize button
    local resizeButton = CreateFrame("Button", nil, addonFrame)
    resizeButton:SetSize(16, 16)
    resizeButton:SetPoint("BOTTOMRIGHT")
    resizeButton:SetNormalTexture("Interface/ChatFrame/UI-ChatIM-SizeGrabber-Up")
    resizeButton:SetHighlightTexture("Interface/ChatFrame/UI-ChatIM-SizeGrabber-Highlight")
    resizeButton:SetPushedTexture("Interface/ChatFrame/UI-ChatIM-SizeGrabber-Down")
    resizeButton:SetScript("OnMouseDown", function() addonFrame:StartSizing("BOTTOMRIGHT") end)
    resizeButton:SetScript("OnMouseUp", function() addonFrame:StopMovingOrSizing() end)

    -- Title
    local title = addonFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("TOP", 0, -10)
    title:SetText("Death Tracker")

    -- Tooltip (for commands)
    title:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Commands:\n/hcalerts reset\n/hcalerts show\n/hcalerts hide", nil, nil, nil, nil, true)
        GameTooltip:Show()
    end)
    title:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Scroll frame
    local scrollFrame = CreateFrame("ScrollingMessageFrame", nil, addonFrame)
    scrollFrame:SetSize(180, 260)
    scrollFrame:SetPoint("BOTTOM", 0, 10)
    scrollFrame:SetFontObject(GameFontHighlight)
    scrollFrame:SetJustifyH("LEFT")
    scrollFrame:SetFading(false)
    scrollFrame:SetMaxLines(100)

    -- Cache frames for faster access
    HCA.frameCache.addonFrame = addonFrame
    HCA.frameCache.scrollFrame = scrollFrame
    HCA.frameCache.title = title

    -- Alert text
    local alertText = UIParent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    alertText:SetPoint("TOP", UIParent, "TOP", 0, -150)
    alertText:SetTextColor(1, 1, 1, 0)
    alertText:Hide()
    HCA.frameCache.alertText = alertText

    -- Create animation group once
    local animGroup = alertText:CreateAnimationGroup()
    
    local fadeIn = animGroup:CreateAnimation("Alpha")
    fadeIn:SetOrder(1)
    fadeIn:SetFromAlpha(0)
    fadeIn:SetToAlpha(1)
    fadeIn:SetDuration(0.5)
    fadeIn:SetSmoothing("IN")

    local stay = animGroup:CreateAnimation("Alpha")
    stay:SetOrder(2)
    stay:SetFromAlpha(1)
    stay:SetToAlpha(1)
    stay:SetDuration(3)
    stay:SetSmoothing("NONE")

    local fadeOut = animGroup:CreateAnimation("Alpha")
    fadeOut:SetOrder(3)
    fadeOut:SetFromAlpha(1)
    fadeOut:SetToAlpha(0)
    fadeOut:SetDuration(5)
    fadeOut:SetSmoothing("OUT")

    animGroup:SetScript("OnFinished", function()
        alertText:Hide()
    end)

    HCA.frameCache.animGroup = animGroup

    -- Update scroll frame size function
    local function UpdateScrollFrame()
        scrollFrame:ClearAllPoints()
        scrollFrame:SetPoint("TOPLEFT", addonFrame, "TOPLEFT", 10, -30)
        scrollFrame:SetPoint("BOTTOMRIGHT", addonFrame, "BOTTOMRIGHT", -10, 10)
        scrollFrame:SetSize(addonFrame:GetWidth() - 20, addonFrame:GetHeight() - 40)
    end

    addonFrame:SetScript("OnSizeChanged", UpdateScrollFrame)
    UpdateScrollFrame()

    return addonFrame, scrollFrame, alertText
end

-- Optimized alert display
local function ShowDeathAlert(message)
    local alertText = HCA.frameCache.alertText
    local cleanedMessage = message:gsub("%[(.-)%]", "%1"):gsub("!", "!\n")
    
    alertText:SetText(cleanedMessage)
    alertText:SetTextScale(1.5)
    alertText:SetAlpha(0)
    alertText:Show()
    
    HCA.frameCache.animGroup:Play()
end

-- Optimized message processing
local function ProcessDeathMessage(message)
    local name, cause, zone, level = match(message, "%[(.-)%](.-) in (.-)! They were level (%d+)")
    
    if not (name and level and cause and zone) then return end
    
    level = tonumber(level)
    local rewordedCause = ""
    
    for _, pattern in pairs(HCA.patterns) do
        local match = string.match(cause, pattern[1])
        if match then
            rewordedCause = pattern[2] or match
            break
        end
    end

    local levelColor, playSound = GetLevelColor(level)
    local deathInfo = format("(%s%s|r) %s - %s - %s", levelColor, level, name, rewordedCause, zone) -- TODO: Rework this to be tab-spaced? Or put it in a table instead?
    
    insert(HCA.deathData, deathInfo)
    if #HCA.deathData > 100 then
        remove(HCA.deathData, 1)
    end
    
    HCA.frameCache.scrollFrame:AddMessage(deathInfo)
    
    if playSound then
        ShowDeathAlert(message)
        PlaySound(8959, "Master")
    end
end

-- Event handling
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("CHAT_MSG_CHANNEL")
eventFrame:SetScript("OnEvent", function(_, _, message, _, _, channelName)
    local channel = match(channelName, "%d+%.%s*(.+)")
    if channel == "HardcoreDeaths" then
        ProcessDeathMessage(message)
    end
end)

-- Initialize UI
local addonFrame, scrollFrame = InitializeUI()

-- Slash commands
SLASH_HARDCOREALERTS1 = "/hcalerts"
SlashCmdList["HARDCOREALERTS"] = function(msg)
    if msg == "reset" then
        HCA.deathData = {}
        scrollFrame:Clear()
        print("Hardcore Alerts: Data reset.")
    elseif msg == "hide" then
        addonFrame:Hide()
    elseif msg == "show" then
        addonFrame:Show()
    end
end