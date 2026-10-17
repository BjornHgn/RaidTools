-- RaidTools : mode édition (/rt unlock). Chaque fenêtre affiche une petite roue de réglages
-- (taille, opacité, afficher / masquer, réinitialiser) et une poignée pour l'agrandir à la souris.
-- Les réglages sont gardés dans ns.db.frames et réappliqués à la connexion.
-- Les barres de calls et de marqueurs contiennent des boutons sécurisés : réglables hors combat seulement.

local _, ns = ...

local GEAR = "Interface\\Worldmap\\Gear_64Grey"
local GRIP = "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up"
local SCALES = { 0.5, 0.7, 0.85, 1, 1.15, 1.3, 1.5, 1.75, 2 }
local ALPHAS = { 0.4, 0.6, 0.8, 1 }
local editing = false

local function Settings(key)
    ns.db.frames[key] = ns.db.frames[key] or {}
    return ns.db.frames[key]
end

-- Une entrée par fenêtre réglable, repérée par son nom global.
local DEFS = {
    {
        name = "RaidToolsAlertFrame", key = "alert", label = "Alertes",
        getScale = function() return ns.db.alert.scale or 1 end,
        setScale = function(f, v) ns.db.alert.scale = v; f:SetScale(v) end,
        -- L'alerte gère sa propre transparence (fondu) : l'opacité s'applique au texte.
        alphaTarget = function(f) return f.text end,
        toggle = { "Afficher les alertes", function() return ns.db.alert.show ~= false end,
            function(v) ns.db.alert.show = v end },
    },
    {
        name = "RaidToolsBarHolder", key = "bars", label = "Barres de temps", noGrip = true,
        toggle = { "Afficher les barres", function() return ns.db.showBars ~= false end,
            function(v) ns.db.showBars = v end },
    },
    {
        name = "RaidToolsTracker", key = "tracker", label = "Suivi de phase",
        toggle = { "Afficher le suivi pendant le boss", function() return ns.db.showTracker end,
            function(v) ns.db.showTracker = v end },
    },
    {
        name = "RaidToolsCallBar", key = "callbar", label = "Barre de calls", secure = true,
        toggle = { "Afficher la barre", function() return RaidToolsCallBar:IsShown() end,
            function(v) ns.ToggleCallBar(v) end },
    },
    {
        name = "RaidToolsMarkerBar", key = "markerbar", label = "Barre de marqueurs", secure = true,
        toggle = { "Afficher la barre", function() return RaidToolsMarkerBar:IsShown() end,
            function(v) ns.ToggleMarkerBar(v) end },
    },
}

local function Blocked(def)
    if def.secure and InCombatLockdown() then
        ns.Print(def.label .. " : réglable seulement hors combat.")
        return true
    end
end

local function GetScale(def, f)
    if def.getScale then return def.getScale() end
    return Settings(def.key).scale or f:GetScale()
end

local function SetScale(def, f, v)
    if Blocked(def) then return end
    v = math.max(0.5, math.min(2, v))
    if def.setScale then def.setScale(f, v) else Settings(def.key).scale = v; f:SetScale(v) end
end

local function SetAlpha(def, f, v)
    if Blocked(def) then return end
    Settings(def.key).alpha = v
    local target = def.alphaTarget and def.alphaTarget(f) or f
    target:SetAlpha(v)
end

local function OpenMenu(gear)
    local def, f = gear.def, gear.target
    MenuUtil.CreateContextMenu(gear, function(_, root)
        root:CreateTitle(def.label)
        local size = root:CreateButton("Taille")
        for _, v in ipairs(SCALES) do
            size:CreateRadio(("%d %%"):format(v * 100 + 0.5),
                function() return math.abs(GetScale(def, f) - v) < 0.01 end,
                function() SetScale(def, f, v) end)
        end
        local alpha = root:CreateButton("Opacité")
        for _, v in ipairs(ALPHAS) do
            alpha:CreateRadio(("%d %%"):format(v * 100 + 0.5),
                function() return math.abs((Settings(def.key).alpha or 1) - v) < 0.01 end,
                function() SetAlpha(def, f, v) end)
        end
        if def.toggle then
            root:CreateCheckbox(def.toggle[1], def.toggle[2], function()
                if Blocked(def) then return end
                def.toggle[3](not def.toggle[2]())
            end)
        end
        root:CreateButton("Réinitialiser taille et opacité", function()
            SetScale(def, f, 1)
            SetAlpha(def, f, 1)
        end)
        root:CreateDivider()
        root:CreateButton("Terminer l'édition", function() ns.SetAlertsLocked(true) end)
    end)
end

local function Tooltip(self, title, text)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(title)
    GameTooltip:AddLine(text, 0.8, 0.8, 0.8, true)
    GameTooltip:Show()
end

local function Attach(def, f)
    -- Réglages enregistrés.
    local saved = Settings(def.key)
    if saved.scale and not def.getScale and not (def.secure and InCombatLockdown()) then f:SetScale(saved.scale) end
    if saved.alpha then
        local target = def.alphaTarget and def.alphaTarget(f) or f
        target:SetAlpha(saved.alpha)
    end

    local gear = CreateFrame("Button", nil, f)
    gear:SetSize(18, 18)
    local level = (f:GetFrameLevel() or 0) + 10
    gear:SetFrameLevel(level)
    if def.noGrip then
        gear:SetPoint("TOPRIGHT", f, "TOPLEFT", -4, 0)
    else
        gear:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)
    end
    gear:SetNormalTexture(GEAR)
    gear:SetHighlightTexture(GEAR)
    gear.def, gear.target = def, f
    gear:SetScript("OnClick", OpenMenu)
    gear:SetScript("OnEnter", function(self) Tooltip(self, def.label, "Taille, opacité, afficher ou masquer.") end)
    gear:SetScript("OnLeave", function() GameTooltip:Hide() end)
    gear:Hide()
    f.rtGear = gear

    if def.noGrip then return end
    -- Poignée : glisser vers la droite agrandit, vers la gauche réduit.
    local grip = CreateFrame("Button", nil, f)
    grip:SetSize(14, 14)
    grip:SetFrameLevel(level)
    grip:SetPoint("BOTTOMRIGHT", -1, 1)
    grip:SetNormalTexture(GRIP)
    grip:SetScript("OnMouseDown", function(self)
        if Blocked(def) then return end
        local x = GetCursorPosition()
        local startX, startScale = x, GetScale(def, f)
        local width = math.max(50, f:GetWidth())
        self:SetScript("OnUpdate", function()
            local cx = GetCursorPosition()
            local dx = (cx - startX) / (UIParent:GetEffectiveScale() * startScale)
            SetScale(def, f, startScale * (1 + dx / width))
        end)
    end)
    grip:SetScript("OnMouseUp", function(self) self:SetScript("OnUpdate", nil) end)
    grip:SetScript("OnHide", function(self) self:SetScript("OnUpdate", nil) end)
    grip:SetScript("OnEnter", function(self) Tooltip(self, "Taille", "Glisse pour agrandir ou réduire.") end)
    grip:SetScript("OnLeave", function() GameTooltip:Hide() end)
    grip:Hide()
    f.rtGrip = grip
end

-- Applique les réglages enregistrés et prépare roues et poignées (fenêtres créées plus tard comprises).
function ns.InitEditMode()
    for _, def in ipairs(DEFS) do
        local f = _G[def.name]
        if f and not f.rtGear then Attach(def, f) end
    end
end

function ns.SetEditMode(on)
    editing = on and true or false
    ns.InitEditMode()
    for _, def in ipairs(DEFS) do
        local f = _G[def.name]
        if f and f.rtGear then
            f.rtGear:SetShown(editing)
            if f.rtGrip then f.rtGrip:SetShown(editing) end
        end
    end
end

function ns.IsEditMode() return editing end
