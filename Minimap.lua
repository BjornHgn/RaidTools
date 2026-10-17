-- RaidTools : icône autour de la minimap.
-- Clic gauche : ouvre / ferme la fenêtre. Clic droit : menu rapide du lead. Glisser : déplace l'icône.

local _, ns = ...

local button

local function UpdatePosition()
    local angle = math.rad(ns.db.minimap.angle or 210)
    local radius = (Minimap:GetWidth() / 2) + 6
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function OnDragUpdate()
    local mx, my = Minimap:GetCenter()
    local scale = Minimap:GetEffectiveScale()
    local cx, cy = GetCursorPosition()
    cx, cy = cx / scale, cy / scale
    ns.db.minimap.angle = math.deg(math.atan2(cy - my, cx - mx)) % 360
    UpdatePosition()
end

-- Menu rapide : les commandes principales du lead, à portée d'un clic droit.
local function OpenQuickMenu(owner)
    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle("|cff3bc4b5RaidTools|r")
        local pull = root:CreateButton("Pull")
        for _, s in ipairs({ 5, 10, 15 }) do
            pull:CreateButton(s .. " secondes", function() ns.Pull(s) end)
        end
        pull:CreateButton("Annuler le pull", function() ns.CancelPull() end)
        local pause = root:CreateButton("Pause")
        for _, m in ipairs({ 5, 10, 15 }) do
            pause:CreateButton(m .. " minutes", function() ns.StartBreak(m) end)
        end
        pause:CreateButton("Annuler la pause", function() ns.CancelBreak() end)
        root:CreateButton("Ready check", function() DoReadyCheck() end)
        root:CreateButton("Vérification des rôles", function() InitiateRolePoll() end)
        root:CreateButton("Qui a l'addon ?", function() ns.VersionCheck() end)
        root:CreateButton("Vérif raid (ready, nourriture, flacon, buffs)", function() ns.ShowRaidCheck(true) end)
        root:CreateButton("Équilibrer les groupes", function() ns.BalanceGroups() end)
        root:CreateButton("Barre de calls", function() ns.ToggleCallBar() end)
        root:CreateButton("Barre de marqueurs", function() ns.ToggleMarkerBar() end)
        -- Les calls de la phase en cours sur la barre (hors combat : en combat, utilise la barre).
        local calls = root:CreateButton("Calls")
        local any = false
        for i = 1, 8 do
            local b = _G["RaidToolsCallButton" .. i]
            local text = b and b:GetAttribute("rt-text")
            if text then
                any = true
                calls:CreateButton(ns.FormatIcons(text), function() ns.Call(text) end)
            end
        end
        if not any then
            for _, text in ipairs(ns.db.calls) do
                calls:CreateButton(text, function() ns.Call(text) end)
            end
        end
        root:CreateDivider()
        root:CreateButton("Ouvrir la fenêtre", function() ns.ToggleUI() end)
        root:CreateButton("Masquer cette icône", function()
            ns.db.minimap.hide = true
            button:Hide()
            ns.Print("icône masquée. |cff3bc4b5/rt minimap|r pour la réafficher.")
        end)
    end)
end

function ns.InitMinimapButton()
    ns.db.minimap = ns.db.minimap or {}
    button = CreateFrame("Button", "RaidToolsMinimapButton", Minimap)
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local icon = button:CreateTexture(nil, "BACKGROUND")
    icon:SetTexture("Interface\\Icons\\Ability_Warrior_RallyingCry")
    icon:SetSize(20, 20)
    icon:SetPoint("TOPLEFT", 7, -5)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")

    button:SetScript("OnClick", function(self, mouse)
        if mouse == "RightButton" then OpenQuickMenu(self) else ns.ToggleUI() end
    end)
    button:SetScript("OnDragStart", function(self) self:SetScript("OnUpdate", OnDragUpdate) end)
    button:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("|cff3bc4b5Raid|rTools")
        GameTooltip:AddLine("Clic gauche : ouvrir la fenêtre", 1, 1, 1)
        GameTooltip:AddLine("Clic droit : pull, pause, ready check, vérif raid, marqueurs, calls", 1, 1, 1)
        GameTooltip:AddLine("Glisser : déplacer l'icône", 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)

    UpdatePosition()
    button:SetShown(not ns.db.minimap.hide)
end

function ns.SetMinimapButtonShown(show)
    ns.db.minimap.hide = not show
    if button then button:SetShown(show) end
end

function ns.ShowMinimapButton()
    ns.db.minimap.hide = false
    if button then button:Show() end
end
