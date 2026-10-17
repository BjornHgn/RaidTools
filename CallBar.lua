-- RaidTools : barre de calls, l'outil du lead pendant le boss.
--
--   PHASE 2                       [Phase suivante]
--   [Annonce 3/12 : Soak : Throw Junk          F1]
--   [SOAK - Throw Junk  F5]  [ADDS - Mushroom   F6]
--   [SPREAD             F7]  [DEFENSIVES        F8]
--   ...
--   (crâne) (croix) (carré) (lune) (triangle) (losange) (cercle) (étoile)
--
-- Tous les boutons sont sécurisés : ils exécutent « /rw TEXTE » comme si tu le tapais,
-- donc l'alerte raid part même en plein boss, visible par tous, avec ou sans l'addon.
-- Les 8 calls suivent le boss sélectionné et la phase : au changement de phase, le bouton
-- Phase (ou sa touche) passe les calls à ceux de la phase suivante, directement dans le code
-- sécurisé du jeu, ce qui marche aussi en combat.

local _, ns = ...

local FLAT = "Interface\\Buttons\\WHITE8x8"
local MAX_CALLS = 8
local W, PAD, GAP = 252, 8, 4
local CALL_W, CALL_H = (252 - 2 * 8 - 4) / 2, 24
local bar, phaseButton, announceButton, phaseLabel
local callButtons, markerButtons = {}, {}
local plan = { phases = { 1 }, labels = { "PHASE 1" }, calls = {} }

-- Marqueurs dans l'ordre du jeu, avec leur nom anglais (compris par tous dans l'alerte raid).
local MARKERS = {
    { 8, "SKULL" }, { 7, "CROSS" }, { 6, "SQUARE" }, { 5, "MOON" },
    { 4, "TRIANGLE" }, { 3, "DIAMOND" }, { 2, "CIRCLE" }, { 1, "STAR" },
}
-- Clic gauche, clic droit, Maj + clic gauche, Maj + clic droit.
local MARKER_VERBS = { "GO TO", "KILL", "STACK ON", "SOAK" }

----------------------------------------------------------------------
-- Plan de calls par phase
----------------------------------------------------------------------

-- Type de mécanique des presets -> call en anglais.
local KIND_CALL = { soak = "SOAK", adds = "ADDS", spread = "SPREAD", frontal = "FRONTAL", knockback = "KNOCKBACK", aoe = "RAID DEFENSIVES" }
-- Pour ces mécaniques, le nom du sort n'aide pas le raid : le call reste générique.
local NO_SPELL = { aoe = true }
local KIND_ORDER = { "soak", "adds", "spread", "frontal", "knockback", "aoe" }
local MAX_AUTO = 6

function ns.PhaseLabel(p)
    p = tonumber(p) or 1
    return p == math.floor(p) and ("PHASE " .. p) or "INTERMISSION"
end

local function AddCall(list, text)
    text = strtrim(text or "")
    if text == "" or #list >= MAX_CALLS then return end
    for _, t in ipairs(list) do
        if t == text then return end
    end
    list[#list + 1] = text
end

-- Calls d'une phase déduits des lignes de rappel (« Soak : Throw Junk », lignes !rw courtes).
local function AutoCalls(entries, phase)
    local names, custom = {}, {}
    for _, e in ipairs(entries) do
        if e.phase == phase then
            local label, spell = e.text:match("^(%a+) : (.+)$")
            local kind = label and strlower(label)
            if kind and KIND_CALL[kind] then
                names[kind] = names[kind] or { n = 0 }
                spell = strtrim((spell:gsub("%s*/.*$", ""):gsub("{%w+}", "")))
                if not names[kind][spell] then
                    names[kind][spell] = true
                    names[kind].n = names[kind].n + 1
                    names[kind].first = names[kind].first or spell
                end
            elseif e.rw and not label and #e.text <= 24 then
                custom[#custom + 1] = strupper(e.text)
            end
        end
    end
    local out = {}
    for _, kind in ipairs(KIND_ORDER) do
        local n = names[kind]
        if n and #out < MAX_AUTO then
            out[#out + 1] = (n.n == 1 and not NO_SPELL[kind]) and (KIND_CALL[kind] .. " - " .. n.first) or KIND_CALL[kind]
        end
    end
    for _, c in ipairs(custom) do
        if #out < MAX_AUTO then AddCall(out, c) end
    end
    return out
end

-- Les calls génériques complètent la liste, sauf ceux déjà couverts (« SOAK » si « SOAK - X » existe).
local function FillGeneric(list)
    for _, g in ipairs(ns.db.calls) do
        local word = strupper(g):match("^(%S+)")
        local covered = false
        for _, t in ipairs(list) do
            if word and strupper(t):find(word, 1, true) then covered = true break end
        end
        if not covered then AddCall(list, g) end
    end
end

-- Renvoie { phases = {1, 1.5, 2...}, labels = {...}, calls = { [k] = {8 textes} } }.
-- Lignes « call TEXTE » ou « call p2 TEXTE » de la note : calls imposés pour cette phase.
function ns.BuildCallPlan(id)
    id = tonumber(id) or 0
    local entries, est = ns.ParseNote(ns.db.notes[id])
    local explicit = est.calls or {}
    local seen, phases = { [1] = true }, { 1 }
    local function Add(p)
        if p and not seen[p] then seen[p] = true; phases[#phases + 1] = p end
    end
    for _, e in ipairs(entries) do Add(e.phase) end
    for p in pairs(est) do if type(p) == "number" then Add(p) end end
    for p in pairs(explicit) do Add(p) end
    table.sort(phases)

    local result = { phases = phases, labels = {}, calls = {} }
    for k, p in ipairs(phases) do
        result.labels[k] = ns.PhaseLabel(p)
        local calls = {}
        if ns.db.bossCalls then
            if explicit[p] then
                for _, t in ipairs(explicit[p]) do AddCall(calls, t) end
            else
                for _, t in ipairs(AutoCalls(entries, p)) do AddCall(calls, t) end
            end
        end
        FillGeneric(calls)
        -- Calls modifiés à la main depuis la barre (clic droit), pour ce boss et cette phase.
        local over = ns.db.callOverrides[id] and ns.db.callOverrides[id][tostring(p)]
        if over then
            for slot, text in pairs(over) do calls[slot] = text end
        end
        result.calls[k] = calls
    end
    result.id = id
    return result
end

----------------------------------------------------------------------
-- Affichage (texte des boutons : autorisé même en combat)
----------------------------------------------------------------------

local function CurrentIndex()
    return phaseButton and phaseButton:GetAttribute("rt-k") or 1
end

function ns.RefreshCallBar()
    if not bar then return end
    local k = CurrentIndex()
    phaseLabel:SetText(ns.PlanPhaseLabel(k))
    local key = ns.KeyText("RaidToolsPhaseButton")
    phaseButton.text:SetText(key and ("Phase suivante |cff808080" .. key .. "|r") or "Phase suivante >>")
    for i, b in ipairs(callButtons) do
        local text = b:GetAttribute("rt-text")
        local bkey = ns.KeyText("RaidToolsCallButton" .. i)
        b.text:SetText(text and (ns.FormatIcons(text) .. (bkey and ("  |cff808080" .. bkey .. "|r") or "")) or "")
        b:SetAlpha(text and 1 or 0.35)
    end
end

-- Calls de la phase k sur les boutons (hors combat ; en combat, c'est le code sécurisé qui le fait).
local function ApplyPhase(k)
    local n = #plan.phases
    phaseButton:SetAttribute("rt-k", k)
    local kk = math.min(k, n)
    for _, b in ipairs(callButtons) do
        local t = b:GetAttribute("rt-p" .. kk)
        b:SetAttribute("rt-text", t)
        b:SetAttribute("macrotext", (t and ns.db.callRaidWarning) and ("/rw " .. t) or nil)
    end
    ns.RefreshCallBar()
end

-- Charge le plan d'un boss dans les boutons sécurisés (uniquement hors combat).
function ns.PrepareCalls(id)
    if not bar or InCombatLockdown() then return false end
    plan = ns.BuildCallPlan(id)
    local n = #plan.phases
    local old = phaseButton.preparedN or 0
    phaseButton:SetAttribute("rt-n", n)
    phaseButton:SetAttribute("rt-last", math.floor(plan.phases[n] or 1))
    phaseButton:SetAttribute("rt-rw", ns.db.callRaidWarning and 1 or nil)
    for k = 1, math.max(n, old) + 1 do
        phaseButton:SetAttribute("rt-label" .. k, plan.labels[k])
    end
    for i, b in ipairs(callButtons) do
        for k = 1, math.max(n, old) do
            b:SetAttribute("rt-p" .. k, plan.calls[k] and plan.calls[k][i] or nil)
        end
    end
    phaseButton.preparedN = n
    ApplyPhase(1)
    return true
end

function ns.GetCallPlan() return plan end

-- Nom de la k-ième phase du plan ; au-delà des phases connues : PHASE (dernière + 1), etc.
function ns.PlanPhaseLabel(k)
    local n = #plan.phases
    if plan.labels[k] then return plan.labels[k] end
    return "PHASE " .. (math.floor(plan.phases[n] or 1) + k - n)
end

-- Hors combat (test, détection auto avant le combat) : aligne les boutons sur la phase d'index k.
function ns.SyncCallPhase(k)
    if not bar or InCombatLockdown() then return false end
    ApplyPhase(k)
    return true
end

-- Phase détectée par l'addon en combat : le code sécurisé n'a pas bougé, on guide le chef.
function ns.PromptPhaseKey(phase)
    if not (bar and bar:IsShown()) then return end
    local key = ns.KeyText("RaidToolsPhaseButton")
    ns.ShowAlert(("|cff3bc4b5%s détectée|r\n|cffaaaaaa%s pour l'alerte raid et les calls de phase|r"):format(
        ns.PhaseLabel(phase), key and ("appuie sur " .. key) or "clique sur Phase suivante"), { color = { 1, 1, 1 } })
end

----------------------------------------------------------------------
-- Marqueurs : calls en un clic (« {rt8} GO TO SKULL {rt8} »)
----------------------------------------------------------------------

local function MarkerText(m, verbIndex)
    return ("{rt%d} %s %s {rt%d}"):format(m[1], MARKER_VERBS[verbIndex], m[2], m[1])
end

local function UpdateMarkerMacros()
    for i, b in ipairs(markerButtons) do
        local m = MARKERS[i]
        local rw = ns.db.callRaidWarning
        b:SetAttribute("macrotext1", rw and ("/rw " .. MarkerText(m, 1)) or nil)
        b:SetAttribute("macrotext2", rw and ("/rw " .. MarkerText(m, 2)) or nil)
        b:SetAttribute("shift-macrotext1", rw and ("/rw " .. MarkerText(m, 3)) or nil)
        b:SetAttribute("shift-macrotext2", rw and ("/rw " .. MarkerText(m, 4)) or nil)
    end
end

-- Option « calls en alerte raid » changée : recharge les macros (hors combat).
function ns.UpdateCallMacros()
    if not bar or InCombatLockdown() then return end
    UpdateMarkerMacros()
    ns.PrepareCalls(ns.selectedEncounter or 0)
end

----------------------------------------------------------------------
-- Création
----------------------------------------------------------------------

----------------------------------------------------------------------
-- Modifier un call depuis la barre
----------------------------------------------------------------------

local editSlot
local EditCall

local function EditBoxOf(popup)
    return popup.editBox or popup.EditBox or (popup.GetEditBox and popup:GetEditBox())
end

-- text vide : le bouton reprend le call par défaut (preset ou génériques).
local function SaveCallEdit(text)
    local s = editSlot
    editSlot = nil
    if not s then return end
    if InCombatLockdown() then
        ns.Print("Impossible en combat : modifie le call après le combat.")
        return
    end
    text = strtrim(text or "")
    local all = ns.db.callOverrides
    all[s.id] = all[s.id] or {}
    local byPhase = all[s.id][s.phase] or {}
    byPhase[s.slot] = text ~= "" and text or nil
    all[s.id][s.phase] = next(byPhase) and byPhase or nil
    if not next(all[s.id]) then all[s.id] = nil end
    local k = CurrentIndex()
    ns.PrepareCalls(s.id)
    ApplyPhase(k)
    if ns.RefreshUI then ns.RefreshUI() end
end

EditCall = function(button, slot)
    if InCombatLockdown() then
        ns.Print("Les calls se modifient hors combat : le jeu verrouille la barre pendant le combat.")
        return
    end
    local kk = math.min(CurrentIndex(), #plan.phases)
    editSlot = { id = plan.id or 0, phase = tostring(plan.phases[kk] or 1), slot = slot,
        current = button:GetAttribute("rt-text") or "" }
    StaticPopupDialogs.RAIDTOOLS_EDIT_CALL = StaticPopupDialogs.RAIDTOOLS_EDIT_CALL or {
        text = "Call %s - %s\n|cffaaaaaaEn anglais, il part tel quel en alerte raid. Vide = call par défaut.|r",
        button1 = OKAY or "OK", button2 = CANCEL or "Annuler", button3 = "Par défaut",
        hasEditBox = true, editBoxWidth = 260, maxLetters = 80,
        timeout = 0, whileDead = true, hideOnEscape = true,
        OnShow = function(self)
            local eb = EditBoxOf(self)
            if eb then
                eb:SetText(editSlot and editSlot.current or "")
                eb:HighlightText()
                eb:SetFocus()
            end
        end,
        OnAccept = function(self)
            local eb = EditBoxOf(self)
            SaveCallEdit(eb and eb:GetText() or "")
        end,
        OnAlt = function() SaveCallEdit("") end,
        OnCancel = function() editSlot = nil end,
        EditBoxOnEnterPressed = function(self)
            SaveCallEdit(self:GetText())
            self:GetParent():Hide()
        end,
        EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
    }
    StaticPopup_Show("RAIDTOOLS_EDIT_CALL", ns.EncounterName(editSlot.id), plan.labels[kk] or "PHASE 1")
end

local function Style(b, bg)
    b:SetBackdrop({ bgFile = FLAT, edgeFile = FLAT, edgeSize = 1 })
    b:SetBackdropColor(unpack(bg or { 0.12, 0.12, 0.15, 1 }))
    b:SetBackdropBorderColor(0.2, 0.2, 0.24, 1)
    b:HookScript("OnEnter", function(self) self:SetBackdropBorderColor(ns.accent[1], ns.accent[2], ns.accent[3], 1) end)
    b:HookScript("OnLeave", function(self) self:SetBackdropBorderColor(0.2, 0.2, 0.24, 1) end)
end

local function SecureButton(name, w, h, font)
    local b = CreateFrame("Button", name, bar, "SecureActionButtonTemplate,BackdropTemplate")
    b:SetSize(w, h)
    Style(b)
    b:SetAttribute("type", "macro")
    ns.RegisterSecureClicks(b)
    b.text = b:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
    b.text:SetPoint("LEFT", 6, 0)
    b.text:SetPoint("RIGHT", -6, 0)
    b.text:SetJustifyH("LEFT")
    b.text:SetWordWrap(false)
    return b
end

local function Tooltip(self)
    if not self.tip then return end
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    for i, line in ipairs(self.tip) do
        GameTooltip:AddLine(line, i == 1 and 1 or 0.8, i == 1 and 1 or 0.8, i == 1 and 1 or 0.8)
    end
    GameTooltip:Show()
end

local function SavePosition()
    local point, _, _, x, y = bar:GetPoint()
    ns.db.callBar.point, ns.db.callBar.x, ns.db.callBar.y = point, x, y
end

function ns.InitCallBar()
    if bar then return end
    if InCombatLockdown() then
        local wait = CreateFrame("Frame")
        wait:RegisterEvent("PLAYER_REGEN_ENABLED")
        wait:SetScript("OnEvent", function(self)
            self:UnregisterAllEvents()
            ns.InitCallBar()
            ns.PrepareAnnounces(ns.selectedEncounter or 0)
        end)
        return
    end
    ns.secureHeader = ns.secureHeader or CreateFrame("Frame", nil, UIParent, "SecureHandlerBaseTemplate")

    bar = CreateFrame("Frame", "RaidToolsCallBar", UIParent, "BackdropTemplate")
    bar:SetBackdrop({ bgFile = FLAT, edgeFile = FLAT, edgeSize = 1 })
    bar:SetBackdropColor(0.05, 0.05, 0.07, 0.88)
    bar:SetBackdropBorderColor(0, 0, 0, 1)
    bar:SetFrameStrata("MEDIUM")
    bar:SetClampedToScreen(true)
    bar:EnableMouse(true)
    bar:SetMovable(true)
    bar:RegisterForDrag("LeftButton")
    -- Elle contient des boutons sécurisés : le jeu interdit de la déplacer en combat.
    bar:SetScript("OnDragStart", function(self)
        if not InCombatLockdown() then self:StartMoving() end
    end)
    bar:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SavePosition()
    end)
    local pos = ns.db.callBar
    bar:SetPoint(pos.point or "LEFT", UIParent, pos.point or "LEFT", pos.x or 40, pos.y or 0)

    local accent = bar:CreateTexture(nil, "ARTWORK")
    accent:SetColorTexture(ns.accent[1], ns.accent[2], ns.accent[3], 1)
    accent:SetPoint("TOPLEFT", 1, -1)
    accent:SetPoint("TOPRIGHT", -1, -1)
    accent:SetHeight(2)

    local y = -PAD
    phaseLabel = bar:CreateFontString(nil, "OVERLAY")
    phaseLabel:SetFont(STANDARD_TEXT_FONT, 15, "OUTLINE")
    phaseLabel:SetTextColor(ns.accent[1], ns.accent[2], ns.accent[3])
    phaseLabel:SetPoint("TOPLEFT", PAD, y - 4)

    -- Phase suivante : « /rw >> PHASE 2 << » puis recalage des rappels, et calls de la phase.
    phaseButton = SecureButton("RaidToolsPhaseButton", 120, 22)
    phaseButton:SetPoint("TOPRIGHT", -PAD - 18, y)
    phaseButton.text:SetJustifyH("CENTER")
    phaseButton.tip = { "Phase suivante", "Alerte raid « >> PHASE 2 << » pour tout le raid,", "rappels recalés et calls de la nouvelle phase." }
    phaseButton:HookScript("OnEnter", Tooltip)
    phaseButton:HookScript("OnLeave", function() GameTooltip:Hide() end)

    local close = CreateFrame("Button", nil, bar)
    close:SetSize(16, 16)
    close:SetPoint("TOPRIGHT", -2, -4)
    close.text = close:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    close.text:SetPoint("CENTER")
    close.text:SetText("×")
    close:SetScript("OnClick", function() ns.ToggleCallBar(false) end)

    y = y - 22 - GAP
    announceButton = SecureButton("RaidToolsAnnounceButton", W - 2 * PAD, 22)
    announceButton:SetPoint("TOPLEFT", PAD, y)
    announceButton.tip = { "Annonce !rw", "Envoie en alerte raid le prochain rappel marqué !rw du boss." }
    announceButton:HookScript("OnEnter", Tooltip)
    announceButton:HookScript("OnLeave", function() GameTooltip:Hide() end)
    ns.SetupAnnounceButton(announceButton)

    y = y - 22 - GAP
    for i = 1, MAX_CALLS do
        local b = SecureButton("RaidToolsCallButton" .. i, CALL_W, CALL_H)
        local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
        b:SetPoint("TOPLEFT", PAD + col * (CALL_W + GAP), y - row * (CALL_H + GAP))
        -- Clic droit ou Alt + clic : modifier ce call (action perso du bouton sécurisé, pas d'alerte raid).
        b:SetAttribute("type2", "rtedit")
        b:SetAttribute("alt-type1", "rtedit")
        b.rtedit = function(self) EditCall(self, i) end
        b.tip = { "Call " .. i, "Clic : alerte raid pour tout le raid.", "Clic droit ou Alt + clic : modifier ce call", "(pour ce boss et cette phase, hors combat)." }
        b:HookScript("OnEnter", Tooltip)
        b:HookScript("OnLeave", function() GameTooltip:Hide() end)
        b:SetScript("PostClick", function(self, mouse)
            if mouse == "RightButton" or IsAltKeyDown() then return end
            local text = self:GetAttribute("rt-text")
            if text then ns.Call(text, self:GetAttribute("macrotext") ~= nil) end
        end)
        SecureHandlerSetFrameRef(phaseButton, "call" .. i, b)
        callButtons[i] = b
    end
    y = y - 4 * (CALL_H + GAP)

    local size = (W - 2 * PAD - 7 * 2) / 8
    for i, m in ipairs(MARKERS) do
        local b = CreateFrame("Button", "RaidToolsMarkerCall" .. i, bar, "SecureActionButtonTemplate")
        b:SetSize(size, size)
        b:SetPoint("TOPLEFT", PAD + (i - 1) * (size + 2), y - 2)
        b:SetAttribute("type", "macro")
        ns.RegisterSecureClicks(b)
        local t = b:CreateTexture(nil, "ARTWORK")
        t:SetAllPoints()
        t:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcon_" .. m[1])
        local hl = b:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.2)
        b.tip = { m[2], "Clic : " .. MARKER_VERBS[1] .. " " .. m[2], "Clic droit : " .. MARKER_VERBS[2] .. " " .. m[2],
            "Maj + clic : " .. MARKER_VERBS[3] .. " " .. m[2], "Maj + clic droit : " .. MARKER_VERBS[4] .. " " .. m[2] }
        b:SetScript("OnEnter", Tooltip)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        b:SetScript("PostClick", function(self, mouse)
            local verb = (mouse == "RightButton" and 2 or 1) + (IsShiftKeyDown() and 2 or 0)
            ns.Call(MarkerText(m, verb), ns.db.callRaidWarning)
        end)
        markerButtons[i] = b
    end
    y = y - size - 4
    local hint = bar:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", PAD, y - 2)
    hint:SetText("Marqueur : clic GO TO · droit KILL · Maj STACK / SOAK")
    y = y - 16
    bar:SetSize(W, -y + PAD - 4)

    -- Avant chaque clic sur Phase (même en combat) : phase suivante, alerte raid et calls de cette phase.
    SecureHandlerWrapScript(phaseButton, "OnClick", ns.secureHeader, [[
        local k = (self:GetAttribute("rt-k") or 1) + 1
        self:SetAttribute("rt-k", k)
        local n = self:GetAttribute("rt-n") or 1
        local label = self:GetAttribute("rt-label" .. k) or ("PHASE " .. ((self:GetAttribute("rt-last") or 1) + k - n))
        local rw = self:GetAttribute("rt-rw")
        local cmd = "/rt phaseidx " .. k
        if rw then cmd = "/rw >> " .. label .. " <<\n" .. cmd end
        self:SetAttribute("macrotext", cmd)
        local kk = k
        if kk > n then kk = n end
        for i = 1, 8 do
            local b = self:GetFrameRef("call" .. i)
            if b then
                local t = b:GetAttribute("rt-p" .. kk)
                b:SetAttribute("rt-text", t)
                if t and rw then
                    b:SetAttribute("macrotext", "/rw " .. t)
                else
                    b:SetAttribute("macrotext", nil)
                end
            end
        end
    ]])
    phaseButton:SetScript("PostClick", function()
        ns.lastOwnWarning = GetTime()
        ns.RefreshCallBar()
    end)

    UpdateMarkerMacros()
    bar:Hide()
    ns.UpdateCallBarVisibility()
    if ns.InitEditMode then ns.InitEditMode() end
end

-- Visible pour le chef et les assistants en raid, sauf si tu l'as affichée ou masquée toi-même.
function ns.UpdateCallBarVisibility()
    if not bar or InCombatLockdown() then return end
    local shown = ns.db.callBar.shown
    if shown == nil then shown = IsInRaid() and ns.IsLeaderOrAssist() end
    bar:SetShown(shown and true or false)
end

function ns.ToggleCallBar(show)
    if not bar then
        ns.Print("La barre de calls sera prête à la sortie du combat.")
        return
    end
    if InCombatLockdown() then
        ns.Print("La barre de calls ne peut pas être affichée ou masquée en combat.")
        return
    end
    if show == nil then show = not bar:IsShown() end
    ns.db.callBar.shown = show
    bar:SetShown(show)
end
