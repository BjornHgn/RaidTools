-- RaidTools : fenêtre principale (style plat, épuré), redimensionnable.
--
-- La fenêtre ne contient aucun bouton sécurisé (ils sont dans la barre de calls) : elle s'ouvre,
-- se ferme (Échap) et se redimensionne aussi en combat. Elle n'est créée qu'à la première ouverture.
-- Chaque onglet défile et se remet en page selon la largeur : les rangées de boutons passent sur
-- deux lignes quand la place manque, les textes reviennent à la ligne, l'éditeur prend la hauteur libre.
-- Seul l'onglet affiché est recalculé, et rien n'est mis à jour tant que la fenêtre est fermée.

local _, ns = ...

local FLAT = "Interface\\Buttons\\WHITE8x8"
local A = ns.accent
local COLORS = {
    bg = { 0.05, 0.05, 0.07, 0.96 },
    panel = { 0.09, 0.09, 0.11, 1 },
    button = { 0.12, 0.12, 0.15, 1 },
    border = { 0.2, 0.2, 0.24, 1 },
    muted = { 0.6, 0.6, 0.65 },
}

local M, GAP, ROW_H = 16, 6, 26           -- marge, espacement, hauteur des boutons
local TOP, BOTTOM, SCROLLBAR = 72, 20, 24 -- titre + onglets, poignée, barre de défilement
local MIN_W, MIN_H, MAX_W, MAX_H = 380, 420, 1000, 1200
local DEFAULT_W, DEFAULT_H = 460, 640

local main
local pages, tabs, tabOrder = {}, {}, {}
local currentPage
local editor

----------------------------------------------------------------------
-- Widgets
----------------------------------------------------------------------

local function Flat(frame, bg, border)
    frame:SetBackdrop({ bgFile = FLAT, edgeFile = FLAT, edgeSize = 1 })
    frame:SetBackdropColor(unpack(bg))
    frame:SetBackdropBorderColor(unpack(border or COLORS.border))
end

local function Button(parent, text, onClick)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(100, ROW_H)
    Flat(b, COLORS.button)
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    b.text:SetPoint("LEFT", 4, 0)
    b.text:SetPoint("RIGHT", -4, 0)
    b.text:SetWordWrap(false)
    b.text:SetText(text)
    b:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(A[1], A[2], A[3], 1)
        self:SetBackdropColor(0.15, 0.17, 0.19, 1)
    end)
    b:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(unpack(COLORS.border))
        self:SetBackdropColor(unpack(COLORS.button))
    end)
    if onClick then b:SetScript("OnClick", onClick) end
    return b
end

-- Titre de section (texte déjà en majuscules : string.upper ne gère pas les accents).
local function Header(parent, text)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetText(text)
    fs:SetTextColor(A[1], A[2], A[3])
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(1, 1, 1, 0.08)
    line:SetHeight(1)
    line:SetPoint("LEFT", fs, "RIGHT", 8, 0)
    line:SetPoint("RIGHT", parent, "RIGHT", -M, 0)
    return fs
end

local function Muted(parent, text)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetTextColor(unpack(COLORS.muted))
    fs:SetJustifyH("LEFT")
    fs:SetText(text)
    return fs
end

local function Check(parent, label, get, set)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(300, 20)
    local box = CreateFrame("Frame", nil, b, "BackdropTemplate")
    box:SetSize(14, 14)
    box:SetPoint("TOPLEFT", 0, -3)
    Flat(box, COLORS.button)
    local fill = box:CreateTexture(nil, "OVERLAY")
    fill:SetPoint("TOPLEFT", 3, -3)
    fill:SetPoint("BOTTOMRIGHT", -3, 3)
    fill:SetColorTexture(A[1], A[2], A[3])
    b.label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    b.label:SetPoint("TOPLEFT", box, "TOPRIGHT", 8, 0)
    b.label:SetJustifyH("LEFT")
    b.label:SetText(label)
    local function Update() fill:SetShown(get() and true or false) end
    b:SetScript("OnClick", function() set(not get()); Update() end)
    b:SetScript("OnShow", Update)
    Update()
    return b
end

local function EditBox(parent, h)
    local e = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
    e:SetSize(100, h or ROW_H)
    Flat(e, COLORS.panel)
    e:SetFontObject(ChatFontNormal)
    e:SetTextInsets(8, 8, 0, 0)
    e:SetAutoFocus(false)
    e:SetScript("OnEscapePressed", e.ClearFocus)
    return e
end

-- Zone de texte multi-lignes avec défilement ; box:Resize(w, h) suit la fenêtre.
local function MultiLine(parent, onChange)
    local box = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    box:SetSize(300, 100)
    Flat(box, COLORS.panel)
    local sf = CreateFrame("ScrollFrame", nil, box, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 8, -8)
    sf:SetPoint("BOTTOMRIGHT", -28, 8)
    local e = CreateFrame("EditBox", nil, sf)
    e:SetMultiLine(true)
    e:SetAutoFocus(false)
    e:SetFontObject(ChatFontNormal)
    e:SetWidth(260)
    e:SetHeight(84)
    e:SetScript("OnEscapePressed", e.ClearFocus)
    e:SetScript("OnTextChanged", function(self, userInput)
        ScrollingEdit_OnTextChanged(self, sf)
        if userInput and onChange then onChange(self:GetText()) end
    end)
    e:SetScript("OnCursorChanged", ScrollingEdit_OnCursorChanged)
    -- Le suivi du curseur ne tourne que pendant la saisie.
    e:SetScript("OnEditFocusGained", function(self)
        self:SetScript("OnUpdate", function(s, elapsed) ScrollingEdit_OnUpdate(s, elapsed, sf) end)
    end)
    e:SetScript("OnEditFocusLost", function(self) self:SetScript("OnUpdate", nil) end)
    sf:SetScrollChild(e)
    box:EnableMouse(true)
    box:SetScript("OnMouseDown", function() e:SetFocus() end)
    box.edit = e
    function box.Resize(_, w, h)
        box:SetSize(w, h)
        e:SetWidth(math.max(40, w - 40))
        e:SetHeight(math.max(20, h - 16))
    end
    return box
end

-- Regroupe les appels rapprochés (frappe au clavier) en un seul, après un court délai.
local function Debounced(delay, fn)
    local pending = false
    return function()
        if pending then return end
        pending = true
        C_Timer.After(delay, function()
            pending = false
            fn()
        end)
    end
end

----------------------------------------------------------------------
-- Mise en page
----------------------------------------------------------------------

-- Rangée(s) de boutons de même largeur : autant de colonnes que la largeur le permet,
-- réparties pour que les lignes soient équilibrées (4 boutons -> 4, 2 + 2, ou 1 par ligne).
local function Grid(list, y, width, minW, h)
    local shown = {}
    for _, b in ipairs(list) do
        if b:IsShown() then shown[#shown + 1] = b end
    end
    local n = #shown
    if n == 0 then return y end
    h = h or ROW_H
    local cols = math.max(1, math.min(n, math.floor((width + GAP) / (minW + GAP))))
    local rows = math.ceil(n / cols)
    cols = math.ceil(n / rows)
    local bw = (width - (cols - 1) * GAP) / cols
    for i, b in ipairs(shown) do
        local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", M + col * (bw + GAP), y - row * (h + GAP))
        b:SetSize(bw, h)
    end
    return y - rows * h - (rows - 1) * GAP
end

local function TextHeight(fs)
    local h = fs:GetStringHeight() or 0
    if h < 1 and (fs:GetText() or "") ~= "" then h = 12 end
    return math.ceil(h)
end

local function PlaceText(fs, y, width, x)
    fs:ClearAllPoints()
    fs:SetPoint("TOPLEFT", x or M, y)
    fs:SetWidth(width)
    return y - TextHeight(fs)
end

local function PlaceHeader(fs, y)
    fs:ClearAllPoints()
    fs:SetPoint("TOPLEFT", M, y)
    return y - 22
end

local function PlaceCheck(c, y, width, x)
    c:ClearAllPoints()
    c:SetPoint("TOPLEFT", x or M, y)
    c.label:SetWidth(width - 22)
    local h = math.max(20, TextHeight(c.label) + 6)
    c:SetSize(width, h)
    return y - h - 2
end

local function Place(frame, y, width, h, x)
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", x or M, y)
    frame:SetSize(width, h)
    return y - h
end

local function ViewSize()
    return main:GetWidth() - SCROLLBAR, main:GetHeight() - TOP - BOTTOM
end

local function LayoutPage(page)
    local viewW, viewH = ViewSize()
    page.content:SetWidth(viewW)
    local y = page.layout(viewW - 2 * M, viewH)
    page.content:SetHeight(math.max(1, -y + 12))
    page.dirty = false
end

-- Données à jour (si quelque chose a changé) puis mise en page (si la taille a changé).
local function ShowPage(page)
    if page.stale then
        page.stale = false
        if page.refresh then page.refresh() end
        page.dirty = true
    end
    if page.dirty then LayoutPage(page) end
end

----------------------------------------------------------------------
-- Choix du boss (partagé par les onglets Raid et Rappels)
----------------------------------------------------------------------

-- Le Journal de donjon ne change pas pendant la session : on ne le parcourt qu'une fois.
local journalList

local function BuildEncounterList()
    if not journalList or #journalList == 0 then
        journalList = {}
        ns.journalEncounters = ns.journalEncounters or {}
        pcall(function()
            local numTiers = EJ_GetNumTiers()
            for tier = numTiers, math.max(1, numTiers - 1), -1 do
                EJ_SelectTier(tier)
                local i = 1
                while true do
                    local instanceID, instanceName = EJ_GetInstanceByIndex(i, true)
                    if not instanceID then break end
                    EJ_SelectInstance(instanceID)
                    local j = 1
                    while true do
                        local name, _, _, _, _, _, dungeonEncounterID = EJ_GetEncounterInfoByIndex(j, instanceID)
                        if not name then break end
                        if dungeonEncounterID and not ns.journalEncounters[dungeonEncounterID] then
                            ns.journalEncounters[dungeonEncounterID] = name
                            journalList[#journalList + 1] = { id = dungeonEncounterID, name = name, group = instanceName }
                        end
                        j = j + 1
                    end
                    i = i + 1
                end
            end
        end)
    end

    local list = { { id = 0, name = "Tous les boss (générique)" } }
    local seen = { [0] = true }
    for _, e in ipairs(journalList) do
        seen[e.id] = true
        list[#list + 1] = e
    end
    local extra = {}
    for id, preset in pairs(ns.Presets or {}) do
        if not seen[id] then seen[id] = true; extra[#extra + 1] = { id = id, name = preset.name, group = "Presets" } end
    end
    for id, name in pairs(ns.db.encounters) do
        if not seen[id] then seen[id] = true; extra[#extra + 1] = { id = id, name = name, group = "Boss rencontrés" } end
    end
    for id in pairs(ns.db.notes) do
        if not seen[id] then seen[id] = true; extra[#extra + 1] = { id = id, name = ns.EncounterName(id), group = "Autres rappels" } end
    end
    table.sort(extra, function(a, b)
        if a.group ~= b.group then return a.group < b.group end
        return a.name < b.name
    end)
    for _, e in ipairs(extra) do list[#list + 1] = e end
    return list
end

local function SelectEncounter(id)
    ns.selectedEncounter = id
    if editor then editor.edit:ClearFocus() end
    if not ns.PrepareAnnounces(id) and InCombatLockdown() then
        ns.Print("La barre de calls passera sur ce boss à la sortie du combat.")
    end
    ns.RefreshUI()
end

local function EncounterDropdown(parent)
    local dd = CreateFrame("DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
    dd:SetWidth(300)
    dd:SetupMenu(function(_, root)
        if root.SetScrollMode then root:SetScrollMode(420) end
        local lastGroup
        for _, e in ipairs(BuildEncounterList()) do
            if e.group and e.group ~= lastGroup then
                root:CreateTitle(e.group)
                lastGroup = e.group
            end
            local text = e.name
            local icon = ns.BossIcons and ns.BossIcons[e.id]
            if icon then text = ("|T%d:16:16:0:0|t %s"):format(icon, text) end
            if ns.db.notes[e.id] then text = text .. "  |cff3bc4b5●|r" end
            root:CreateRadio(text,
                function(id) return (ns.selectedEncounter or 0) == id end,
                SelectEncounter,
                e.id)
        end
    end)
    return dd
end

----------------------------------------------------------------------
-- Onglet Raid
----------------------------------------------------------------------

local function BuildRaidPage(page)
    local c = page.content
    local db = ns.db

    local hBoss = Header(c, "BOSS")
    local boss = EncounterDropdown(c)

    local hPull = Header(c, "PULL")
    local pull = {}
    for _, s in ipairs({ 5, 10, 15 }) do pull[#pull + 1] = Button(c, "Pull " .. s .. " s", function() ns.Pull(s) end) end
    pull[#pull + 1] = Button(c, "Annuler", function() ns.CancelPull() end)

    local hBreak = Header(c, "PAUSE")
    local breaks = {}
    for _, m in ipairs({ 5, 10, 15 }) do breaks[#breaks + 1] = Button(c, m .. " min", function() ns.StartBreak(m) end) end
    breaks[#breaks + 1] = Button(c, "Annuler", function() ns.CancelBreak() end)

    local hGroup = Header(c, "GROUPE")
    local group = {
        Button(c, "Ready check", function() DoReadyCheck() end),
        Button(c, "Rôles", function() InitiateRolePoll() end),
        Button(c, "Qui a l'addon ?", function() ns.VersionCheck() end),
        Button(c, "Vérif raid", function() ns.ShowRaidCheck() end),
    }

    local hCalls = Header(c, "CALLS EN COMBAT")
    local info = Muted(c, "La barre de calls envoie tes calls en alerte raid, même pendant le boss : tout le raid les voit, avec ou sans l'addon. " ..
        "Phase suivante (ou sa touche) annonce la phase et passe aux calls de cette phase. " ..
        "Marqueurs : clic GO TO, clic droit KILL, Maj + clic STACK ON, Maj + clic droit SOAK.")
    local bars = {
        Button(c, "Barre de calls", function() ns.ToggleCallBar() end),
        Button(c, "Barre de marqueurs", function() ns.ToggleMarkerBar() end),
    }
    local auto = Check(c, "Afficher la barre de calls quand je suis chef ou assistant en raid",
        function() return db.callBar.shown == nil end,
        function(v)
            if v then
                db.callBar.shown = nil
            else
                db.callBar.shown = RaidToolsCallBar and RaidToolsCallBar:IsShown() or false
            end
            ns.UpdateCallBarVisibility()
        end)

    -- Aperçu des calls que la barre proposera, phase par phase.
    local planTitle = Muted(c, "")
    local planLines = {}

    local free = EditBox(c, 28)
    free.placeholder = Muted(free, "Call libre en anglais, puis Entrée...")
    free.placeholder:SetPoint("LEFT", 8, 0)
    free:SetScript("OnTextChanged", function(self) self.placeholder:SetShown(self:GetText() == "") end)
    local function SendFree()
        ns.Call(free:GetText())
        free:SetText("")
        free:ClearFocus()
    end
    free:SetScript("OnEnterPressed", SendFree)
    local send = Button(c, "Envoyer", SendFree)

    local rw = Check(c, "Envoyer les calls en alerte raid (/rw)",
        function() return db.callRaidWarning end,
        function(v)
            db.callRaidWarning = v
            ns.UpdateCallMacros()
        end)
    local bossCalls = Check(c, "Calls adaptés au boss et à la phase (sinon : calls génériques)",
        function() return db.bossCalls end,
        function(v)
            db.bossCalls = v
            ns.PrepareCalls(ns.selectedEncounter or 0)
            ns.RefreshUI()
        end)

    page.refresh = function()
        boss:GenerateMenu()
        local id = ns.selectedEncounter or 0
        local plan = ns.BuildCallPlan(id)
        planTitle:SetText(("Calls de la barre pour |cffffffff%s|r :"):format(ns.EncounterName(id)))
        for k = 1, math.max(#plan.phases, #planLines) do
            local fs = planLines[k]
            if k <= #plan.phases then
                if not fs then
                    fs = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                    fs:SetJustifyH("LEFT")
                    planLines[k] = fs
                end
                local calls = {}
                for slot = 1, 8 do
                    local t = plan.calls[k] and plan.calls[k][slot]
                    if t and t ~= "" then calls[#calls + 1] = t end
                end
                local text = #calls > 0 and table.concat(calls, "  ·  ") or "|cff808080(aucun)|r"
                fs:SetText(("|cff3bc4b5%s|r   %s"):format(plan.labels[k], ns.FormatIcons(text)))
                fs:Show()
            elseif fs then
                fs:Hide()
            end
        end
        page.planCount = #plan.phases
    end

    page.layout = function(width)
        local y = -12
        y = PlaceHeader(hBoss, y)
        y = Place(boss, y, width, 26) - 12
        y = PlaceHeader(hPull, y)
        y = Grid(pull, y, width, 72) - 12
        y = PlaceHeader(hBreak, y)
        y = Grid(breaks, y, width, 72) - 12
        y = PlaceHeader(hGroup, y)
        y = Grid(group, y, width, 100) - 12
        y = PlaceHeader(hCalls, y)
        y = PlaceText(info, y, width) - 8
        y = Grid(bars, y, width, 130) - 6
        y = PlaceCheck(auto, y, width) - 8
        y = PlaceText(planTitle, y, width) - 4
        for k = 1, page.planCount or 0 do
            y = PlaceText(planLines[k], y, width - 8, M + 8) - 3
        end
        y = y - 9
        Place(free, y, width - 100 - GAP, 28)
        Place(send, y, 100, 28, M + width - 100)
        y = y - 28 - 8
        y = PlaceCheck(rw, y, width)
        y = PlaceCheck(bossCalls, y, width)
        return y
    end
end

----------------------------------------------------------------------
-- Onglet Rappels
----------------------------------------------------------------------

local HELP = "Une ligne par rappel :  |cffffffff1:30 Soak left @tank !rw|r\n" ..
    "@cible : pseudo, tank, heal, dps, melee, ranged, classe, g1 à g8 ou all\n" ..
    "|cffffffffrc Soak left @g1,g2|r : assignation montrée au ready check\n" ..
    "!rw : le chef l'annonce aussi en alerte raid.  # = commentaire\n" ..
    "Phases : |cffffffffphase 2 3:10|r (début estimé) puis |cffffffffp2 0:30 Texte|r\n" ..
    "Calls de la barre : |cffffffffcall p2 SOAK LEFT|r (sinon déduits du preset)\n" ..
    "Ce qui part au raid (!rw, rc, call) : en anglais, compris de tous."

local function BuildRemindersPage(page)
    local c = page.content
    ns.selectedEncounter = ns.selectedEncounter or 0

    local label = Muted(c, "Boss")
    local received = Muted(c, "")
    received:SetJustifyH("RIGHT")
    local boss = EncounterDropdown(c)

    -- Presets du raid actuel (Héroïque / Mythique), chargés dans l'éditeur pour être adaptés.
    local presetLabel = Muted(c, "Preset :")
    local presetButtons = {}
    for _, def in ipairs({ { 15, "Héroïque" }, { 16, "Mythique" } }) do
        local diff = def[1]
        local b = Button(c, def[2], function()
            local text = ns.BuildPresetNote(ns.selectedEncounter, diff)
            if not text then return end
            local function Apply()
                ns.db.notes[ns.selectedEncounter] = text
                editor.edit:SetText(text)
                ns.PrepareAnnounces(ns.selectedEncounter)
                ns.RefreshUI()
            end
            if ns.db.notes[ns.selectedEncounter] then
                StaticPopupDialogs.RAIDTOOLS_PRESET = StaticPopupDialogs.RAIDTOOLS_PRESET or {
                    text = "Remplacer les rappels de ce boss par le preset ?",
                    button1 = YES, button2 = NO, timeout = 0, whileDead = true, hideOnEscape = true,
                }
                StaticPopupDialogs.RAIDTOOLS_PRESET.OnAccept = Apply
                StaticPopup_Show("RAIDTOOLS_PRESET")
            else
                Apply()
            end
        end)
        b.diff = diff
        presetButtons[#presetButtons + 1] = b
    end
    local noPreset = Muted(c, "aucun pour ce boss")
    local bossAlerts = Check(c, "Mes alertes pour ce boss (les annonces !rw pour le raid restent)",
        function() return not ns.db.muteBosses[ns.selectedEncounter or 0] end,
        function(v) ns.db.muteBosses[ns.selectedEncounter or 0] = (not v) or nil end)

    local prepare = Debounced(0.5, function() ns.PrepareAnnounces(ns.selectedEncounter or 0) end)
    editor = MultiLine(c, function(text)
        ns.db.notes[ns.selectedEncounter] = (strtrim(text) ~= "") and text or nil
        prepare()
        if pages.raid then pages.raid.stale = true end
        if ns.db.received[ns.selectedEncounter] then
            ns.db.received[ns.selectedEncounter] = nil
            received:SetText("")
        end
    end)

    local help = Muted(c, HELP)

    local buttons = {
        Button(c, "Tester", function()
            editor.edit:ClearFocus()
            ns.StartReminders(ns.selectedEncounter, true)
        end),
        Button(c, "Arrêter", function() ns.StopReminders() end),
        -- Colle une note MRT ou NSRT dans l'éditeur puis clique ici : elle est convertie et rangée sous le bon boss.
        Button(c, "Importer", function()
            local text = editor.edit:GetText()
            local id, converted, count, kind
            if ns.IsMRTNote(text) then
                id, kind = ns.selectedEncounter, "MRT"
                converted, count = ns.ConvertMRTNote(text, id)
            elseif ns.IsNSRTNote(text) then
                local encID
                encID, converted, count = ns.ConvertNSRTNote(text)
                id, kind = encID or ns.selectedEncounter, "NSRT"
            else
                ns.Print("Colle d'abord une note MRT (lignes {time:1:30} ...) ou NSRT (time:...;tag:...;text:...) dans l'éditeur.")
                return
            end
            ns.selectedEncounter = id
            ns.db.notes[id] = converted
            editor.edit:SetText(converted)
            ns.PrepareAnnounces(id)
            ns.RefreshUI()
            ns.Print(("Note %s importée pour %s : %d ligne(s)."):format(kind, ns.EncounterName(id), count))
        end),
        Button(c, "Envoyer au raid", function() ns.ShareNote(ns.selectedEncounter) end),
    }

    page.refresh = function()
        boss:GenerateMenu()
        local r = ns.db.received[ns.selectedEncounter]
        received:SetText(r and ("|cff3bc4b5Reçu de %s à %s|r"):format(r.from, r.at) or "")
        local any = false
        for _, b in ipairs(presetButtons) do
            local has = ns.HasPreset(ns.selectedEncounter, b.diff)
            b:SetShown(has)
            any = any or has
        end
        noPreset:SetShown(not any)
        bossAlerts:GetScript("OnShow")(bossAlerts)
        if not editor.edit:HasFocus() then editor.edit:SetText(ns.db.notes[ns.selectedEncounter] or "") end
    end

    page.layout = function(width, viewH)
        local y = -14
        label:ClearAllPoints()
        label:SetPoint("TOPLEFT", M, y)
        received:ClearAllPoints()
        received:SetPoint("TOPRIGHT", c, "TOPLEFT", M + width, y)
        received:SetWidth(math.max(40, width - 60))
        y = Place(boss, y - 16, width, 26) - 6
        y = PlaceCheck(bossAlerts, y, width) - 6

        presetLabel:ClearAllPoints()
        presetLabel:SetPoint("TOPLEFT", M, y - 6)
        noPreset:ClearAllPoints()
        noPreset:SetPoint("TOPLEFT", M + 60, y - 6)
        local shown = {}
        for _, b in ipairs(presetButtons) do
            if b:IsShown() then shown[#shown + 1] = b end
        end
        local bw = math.min(110, (width - 60 - GAP) / 2)
        for i, b in ipairs(shown) do
            Place(b, y, bw, 24, M + 60 + (i - 1) * (bw + GAP))
        end
        y = y - 24 - 10

        -- L'éditeur prend la hauteur restante (au moins 140 px) ; l'aide et les boutons restent visibles.
        help:SetWidth(width)
        local cols = math.max(1, math.min(4, math.floor((width + GAP) / (90 + GAP))))
        local rows = math.ceil(#buttons / cols)
        local below = 8 + TextHeight(help) + 10 + rows * ROW_H + (rows - 1) * GAP + 12
        local edH = math.max(140, math.floor(viewH + y - below))
        editor:ClearAllPoints()
        editor:SetPoint("TOPLEFT", M, y)
        editor:Resize(width, edH)
        y = y - edH - 8
        y = PlaceText(help, y, width) - 10
        return Grid(buttons, y, width, 90, ROW_H)
    end
end

----------------------------------------------------------------------
-- Onglet Outils
----------------------------------------------------------------------

local function BuildToolsPage(page)
    local c = page.content
    local db = ns.db

    local hCheck = Header(c, "VÉRIF RAID")
    local checkInfo = Muted(c, "Une fenêtre avec une ligne par joueur : ready check, nourriture, flacon, rune et buffs de raid. « Poster au raid » envoie les manques dans le chat raid, en anglais.")
    local checkNow = Button(c, "Ouvrir la vérif raid", function() ns.ShowRaidCheck(true) end)
    local checkAuto = Check(c, "Chef : ouvrir la vérif raid au ready check (rien n'est posté dans le chat)",
        function() return db.raidCheckOnReady end,
        function(v) db.raidCheckOnReady = v end)

    local hGroups = Header(c, "GROUPES")
    local groupsInfo = Muted(c, "Répartit tanks, soigneurs, mêlées et distances à parts égales entre la moitié gauche (G1-G2) et la moitié droite (G3-G4, ou G1-G3 / G4-G6 en normal et héroïque), pour des soaks justes par groupe. Le résultat est annoncé dans le chat raid. Chef de raid, hors combat.")
    local balance = Button(c, "Équilibrer les groupes", function() ns.BalanceGroups() end)

    local hAssist = Header(c, "ASSIST AUTOMATIQUE")
    local assistLabel = Muted(c, "Pseudos à passer assistant dès qu'ils sont dans le raid (séparés par des virgules) :")
    local assist = EditBox(c, 26)
    assist:SetText(db.autoAssist or "")
    assist:SetScript("OnTextChanged", function(self, userInput)
        if userInput then db.autoAssist = strtrim(self:GetText()) end
    end)
    assist:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        ns.AutoAssistPass()
    end)

    local hMarkers = Header(c, "MARQUEURS")
    local markersInfo = Muted(c, "Une petite barre déplaçable : marqueurs sur la cible et au sol. Clic gauche pose, clic droit retire. Elle marche aussi en combat.")
    local markersButton = Button(c, "Afficher / masquer la barre", function() ns.ToggleMarkerBar() end)

    local hInvite = Header(c, "INVITATIONS")
    local inviteCheck = Check(c, "Inviter qui me chuchote le mot :",
        function() return db.autoInvite end,
        function(v)
            db.autoInvite = v
            ns.UpdateInviter()
        end)
    local word = EditBox(c, 24)
    word:SetText(db.inviteKeyword or "inv")
    word:SetScript("OnTextChanged", function(self) db.inviteKeyword = strtrim(self:GetText()) end)
    word:SetScript("OnEnterPressed", word.ClearFocus)
    local inviteInfo = Muted(c, "Le groupe passe en raid tout seul. Il faut être chef ou assistant.")

    local hLog = Header(c, "JOURNAL DE COMBAT")
    local logCheck = Check(c, "Journal de combat auto en raid (fichier pour Warcraft Logs)",
        function() return db.autoLog end,
        function(v) db.autoLog = v end)
    local logInfo = Muted(c, "L'addon n'affiche pas les logs : il lance l'enregistrement du jeu en entrant en raid et l'arrête en sortant. " ..
        "Le fichier est dans World of Warcraft\\_retail_\\Logs\\WoWCombatLog-*.txt. Envoie-le sur warcraftlogs.com avec l'appli Warcraft Logs (Uploader).")

    local hMods = Header(c, "JOUEURS AVEC MRT, DBM OU BIGWIGS")
    local mrtCheck = Check(c, "Envoyer ma note de boss aux joueurs qui ont MRT",
        function() return db.mrtNote end,
        function(v) db.mrtNote = v end)
    local timersCheck = Check(c, "Barres de pull et de pause chez les joueurs DBM / BigWigs",
        function() return db.bossModTimers end,
        function(v) db.bossModTimers = v end)
    local modsInfo = Muted(c, "La note MRT reprend tes assignations rc, les lignes !rw et tes propres lignes, avec les temps de MRT. Elle part avec tes rappels : ready check, pull ou Envoyer au raid.")
    local mrtButton = Button(c, "Envoyer la note MRT", function()
        if ns.SendMRTNote(ns.selectedEncounter or 0, true) then
            ns.Print(("Note MRT de %s envoyée."):format(ns.EncounterName(ns.selectedEncounter or 0)))
        end
    end)

    page.refresh = function()
        if not assist:HasFocus() then assist:SetText(db.autoAssist or "") end
    end

    page.layout = function(width)
        local half = math.min(width, 220)
        local y = -12
        y = PlaceHeader(hCheck, y)
        y = PlaceText(checkInfo, y, width) - 8
        y = Place(checkNow, y, half, ROW_H) - 6
        y = PlaceCheck(checkAuto, y, width) - 12

        y = PlaceHeader(hGroups, y)
        y = PlaceText(groupsInfo, y, width) - 8
        y = Place(balance, y, half, ROW_H) - 14

        y = PlaceHeader(hAssist, y)
        y = PlaceText(assistLabel, y, width) - 6
        y = Place(assist, y, width, 26) - 14

        y = PlaceHeader(hMarkers, y)
        y = PlaceText(markersInfo, y, width) - 8
        y = Place(markersButton, y, half, ROW_H) - 14

        y = PlaceHeader(hInvite, y)
        local wordW = 90
        PlaceCheck(inviteCheck, y - 2, width - wordW - GAP)
        Place(word, y, wordW, 24, M + width - wordW)
        y = y - math.max(24, inviteCheck:GetHeight() + 2) - 6
        y = PlaceText(inviteInfo, y, width) - 14

        y = PlaceHeader(hLog, y)
        y = PlaceCheck(logCheck, y, width) - 4
        y = PlaceText(logInfo, y, width) - 12

        y = PlaceHeader(hMods, y)
        y = PlaceCheck(mrtCheck, y, width)
        y = PlaceCheck(timersCheck, y, width) - 6
        y = PlaceText(modsInfo, y, width) - 8
        y = Place(mrtButton, y, half, ROW_H)
        return y
    end
end

----------------------------------------------------------------------
-- Onglet Options
----------------------------------------------------------------------

local function Stepper(parent, labelFn, onMinus, onPlus)
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(280, 24)
    local minus = Button(f, "-", function() onMinus(); f.label:SetText(labelFn()) end)
    minus:SetSize(24, 24)
    minus:SetPoint("LEFT")
    f.label = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.label:SetPoint("LEFT", minus, "RIGHT", 8, 0)
    f.label:SetWidth(200)
    f.label:SetText(labelFn())
    local plus = Button(f, "+", function() onPlus(); f.label:SetText(labelFn()) end)
    plus:SetSize(24, 24)
    plus:SetPoint("LEFT", f.label, "RIGHT", 8, 0)
    return f
end

local function ClassHex(class)
    local c = class and ((C_ClassColor and C_ClassColor.GetClassColor and C_ClassColor.GetClassColor(class))
        or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]))
    if not c then return "ffffff" end
    return ("%02x%02x%02x"):format(c.r * 255, c.g * 255, c.b * 255)
end

local function BuildPullsPage(page)
    local c = page.content
    local db = ns.db
    local hList = Header(c, "DERNIERS PULLS")
    local info = Muted(c, "Ce que l'addon voit pendant le boss : durée, kill ou wipe, morts et rez dans l'ordre, phases et calls. " ..
        "Le jeu interdit aux addons de lire le fichier de log : pour les dégâts, les soins et ce qui a tué chaque joueur, " ..
        "ouvre LecteurLogs.html (dossier de l'addon) dans ton navigateur et dépose-y ton fichier WoWCombatLog.")
    local empty = Muted(c, "Aucun pull enregistré pour l'instant.")
    local rows = {}
    local hDetail = Header(c, "DÉTAIL")
    local detail = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    detail:SetJustifyH("LEFT")
    detail:SetSpacing(3)
    local actions = {
        Button(c, "Poster au raid", function() ns.PostPull(db.history[ns.historySelected or 1]) end),
        Button(c, "Effacer l'historique", function() ns.ClearHistory() end),
    }
    local shown = 0

    local function Row(i)
        local b = rows[i]
        if not b then
            b = Button(c, "", function(self)
                ns.historySelected = self.index
                ns.RefreshUI()
            end)
            b.text:SetJustifyH("LEFT")
            rows[i] = b
        end
        return b
    end

    page.refresh = function()
        local list = db.history
        local sel = math.min(ns.historySelected or 1, math.max(1, #list))
        shown = math.min(#list, 15)
        for i = 1, math.max(shown, #rows) do
            if i <= shown then
                local p = list[i]
                local b = Row(i)
                b.index = i
                local diff = ns.DiffShort(p.diff)
                b.text:SetText(("|cff808080%s|r  %s%s   %s %s   |cffaaaaaa%d mort%s|r"):format(
                    date("%d/%m %H:%M", p.date or 0), p.name or "?", diff and (" (" .. diff .. ")") or "",
                    p.kill and "|cff55ff55Kill|r" or "|cffff5555Wipe|r", ns.Clock(p.dur), p.deaths or 0,
                    (p.deaths or 0) > 1 and "s" or ""))
                b:SetBackdropBorderColor(unpack(i == sel and { A[1], A[2], A[3], 1 } or COLORS.border))
                b:Show()
            elseif rows[i] then
                rows[i]:Hide()
            end
        end
        empty:SetShown(#list == 0)
        local p = list[sel]
        local lines = {}
        if p then
            lines[1] = ("|cff3bc4b50:00|r  Pull : %s"):format(p.name or "?")
            for _, e in ipairs(p.events) do
                local t, kind, text, class = e[1], e[2], e[3], e[4]
                local what
                if kind == "death" then
                    what = ("|cffff5555Mort|r : |cff%s%s|r"):format(ClassHex(class), text)
                elseif kind == "rez" then
                    what = ("|cff55ff55Rez|r : |cff%s%s|r"):format(ClassHex(class), text)
                elseif kind == "phase" then
                    what = ("|cff3bc4b5%s|r"):format(text)
                else
                    what = "Call : " .. ns.FormatIcons(text)
                end
                lines[#lines + 1] = ("|cff3bc4b5%s|r  %s"):format(ns.Clock(t), what)
            end
            lines[#lines + 1] = ("|cff3bc4b5%s|r  %s (%d mort%s)"):format(ns.Clock(p.dur),
                p.kill and "|cff55ff55Kill|r" or "|cffff5555Wipe|r", p.deaths or 0, (p.deaths or 0) > 1 and "s" or "")
        end
        detail:SetText(table.concat(lines, "\n"))
        hDetail:SetShown(p ~= nil)
        detail:SetShown(p ~= nil)
        for _, b in ipairs(actions) do b:SetShown(p ~= nil) end
    end

    page.layout = function(width)
        local y = -12
        y = PlaceHeader(hList, y)
        y = PlaceText(info, y, width) - 8
        if empty:IsShown() then y = PlaceText(empty, y, width) - 8 end
        for i = 1, shown do y = Place(rows[i], y, width, 24) - 3 end
        if detail:IsShown() then
            y = PlaceHeader(hDetail, y - 9)
            y = PlaceText(detail, y, width) - 10
            y = Grid(actions, y, width, 140)
        end
        return y
    end
end

local function BuildOptionsPage(page)
    local c = page.content
    local db = ns.db

    -- Fenêtres et voix : un interrupteur chacune.
    local hWindows = Header(c, "FENÊTRES ET VOIX")
    local function SecureToggle(fn)
        return function(v)
            if InCombatLockdown() then ns.Print("Impossible en combat : réessaie après.") return end
            fn(v)
        end
    end
    local windowChecks = {}
    for _, def in ipairs({
        { "Voix (synthèse vocale, sons perso et décomptes)", function() return db.alert.tts end, function(v) db.alert.tts = v end },
        { "Lancer rappels, chrono et suivi tout seuls au pull (sinon : bouton Tester ou rien)", function() return db.autoStart end, function(v) db.autoStart = v end },
        { "Fenêtre de suivi (chrono du combat, phase, prochaines mécaniques)", function() return db.showTracker end, function(v)
            db.showTracker = v
            if not v and RaidToolsTracker then RaidToolsTracker:Hide() end
        end },
        { "Barres de temps (pause, rappels)", function() return db.showBars ~= false end, function(v)
            db.showBars = v
            if not v then ns.StopAllBars() end
        end },
        { "Alertes au centre de l'écran", function() return db.alert.show ~= false end, function(v) db.alert.show = v end },
        { "Barre de calls", function() return RaidToolsCallBar and RaidToolsCallBar:IsShown() end, SecureToggle(function(v) ns.ToggleCallBar(v) end) },
        { "Barre de marqueurs", function() return RaidToolsMarkerBar and RaidToolsMarkerBar:IsShown() end, SecureToggle(function(v) ns.ToggleMarkerBar(v) end) },
        { "Icône de la minimap", function() return not db.minimap.hide end, function(v) ns.SetMinimapButtonShown(v) end },
    }) do
        windowChecks[#windowChecks + 1] = Check(c, def[1], def[2], def[3])
    end

    local hAlerts = Header(c, "ALERTES")
    local checks = {}
    for _, def in ipairs({
        { "Son d'alerte", function() return db.alert.sound end, function(v) db.alert.sound = v end },
        { "Rappels de boss activés", function() return db.reminders.enabled end, function(v) db.reminders.enabled = v end },
        { "Chef : annoncer les rappels !rw en alerte raid", function() return db.reminders.autoRaidWarning end, function(v) db.reminders.autoRaidWarning = v end },
        { "Annoncer pull et pauses en alerte raid", function() return db.pullRaidWarning end, function(v) db.pullRaidWarning = v; db.breakAnnounce = v end },
        { "Accepter les rappels envoyés par le chef", function() return db.acceptShared end, function(v) db.acceptShared = v end },
        { "Afficher en grand (avec la voix) les alertes raid du chef", function() return db.showRaidWarnings end, function(v) db.showRaidWarnings = v end },
        { "Chef : poster les assignations (rc) dans le chat raid au ready check", function() return db.postAssignments end, function(v) db.postAssignments = v end },
        { "Chef : envoyer mes rappels au ready check et au pull", function() return db.autoShare end, function(v) db.autoShare = v end },
        { "Vérifier nourriture et réparations au ready check", function() return db.readyCheckReport end, function(v) db.readyCheckReport = v end },
    }) do
        checks[#checks + 1] = Check(c, def[1], def[2], def[3])
    end

    local steppers = {
        Stepper(c, function() return ("Anticipation des rappels : %d s"):format(db.reminders.lead) end,
            function() db.reminders.lead = math.max(0, db.reminders.lead - 1) end,
            function() db.reminders.lead = math.min(30, db.reminders.lead + 1) end),
        Stepper(c, function()
                local n = db.reminders.countdown or 0
                return n > 0 and ("Décompte vocal des rappels : %d s"):format(n) or "Décompte vocal des rappels : non"
            end,
            function() db.reminders.countdown = math.max(0, (db.reminders.countdown or 0) - 1) end,
            function() db.reminders.countdown = math.min(5, (db.reminders.countdown or 0) + 1) end),
        Stepper(c, function() return ("Taille des alertes : %d %%"):format(db.alert.scale * 100 + 0.5) end,
            function() db.alert.scale = math.max(0.5, db.alert.scale - 0.1); RaidToolsAlertFrame:SetScale(db.alert.scale) end,
            function() db.alert.scale = math.min(2, db.alert.scale + 0.1); RaidToolsAlertFrame:SetScale(db.alert.scale) end),
    }

    local actions = {
        Button(c, "Aperçu / déplacer", function(self)
            local unlocking = RaidToolsAlertFrame:IsMouseEnabled() == false
            ns.SetAlertsLocked(not unlocking)
            self.text:SetText(unlocking and "Valider la position" or "Aperçu / déplacer")
        end),
        Button(c, "Créer les macros de call", function() ns.CreateCallMacros() end),
    }

    -- Types d'alertes : décoche ce que tu ne veux plus voir ni entendre.
    local hKinds = Header(c, "ALERTES À AFFICHER")
    local kindChecks = {}
    for _, def in ipairs({
        { "tank", "Tankbusters" }, { "aoe", "AoE" }, { "soak", "Soaks" }, { "adds", "Adds" },
        { "spread", "Spreads" }, { "frontal", "Frontaux" }, { "knock", "Knockbacks" }, { "absorb", "Absorbs" },
        { "debuff", "Debuffs" }, { "phase", "Changements de phase" }, { "custom", "Mes rappels perso" }, { "break", "Pauses" },
    }) do
        local kind = def[1]
        kindChecks[#kindChecks + 1] = Check(c, def[2],
            function() return not db.muteKinds[kind] end,
            function(v) db.muteKinds[kind] = (not v) or nil end)
    end
    local kindsInfo = Muted(c, "Par boss : case « Mes alertes pour ce boss » dans Rappels. Tes annonces !rw pour le raid partent toujours.")

    -- Alertes une par une, pour le boss choisi.
    local hOne = Header(c, "ALERTES UNE PAR UNE")
    local oneBoss = EncounterDropdown(c)
    local oneEmpty = Muted(c, "Aucun rappel pour ce boss : charge un preset ou écris tes lignes dans Rappels.")
    local function Muted_(id) return ns.db.muteAlerts[id] end
    local oneAll = {
        Button(c, "Tout activer", function()
            ns.db.muteAlerts[ns.selectedEncounter or 0] = nil
            page.stale = true
            ShowPage(page)
        end),
        Button(c, "Tout couper", function()
            local id = ns.selectedEncounter or 0
            local m = {}
            for _, item in ipairs(ns.ListAlerts(id)) do m[item.text] = true end
            ns.db.muteAlerts[id] = next(m) and m or nil
            page.stale = true
            ShowPage(page)
        end),
    }
    local oneChecks, oneItems = {}, {}

    page.refresh = function()
        oneBoss:GenerateMenu()
        local id = ns.selectedEncounter or 0
        oneItems = ns.ListAlerts(id)
        for i, item in ipairs(oneItems) do
            local ch = oneChecks[i]
            if not ch then
                ch = Check(c, "",
                    function() local m = Muted_(ns.selectedEncounter or 0); return not (m and ch and m[ch.alertText]) end,
                    function(v)
                        local eid = ns.selectedEncounter or 0
                        local m = ns.db.muteAlerts[eid] or {}
                        m[ch.alertText] = (not v) or nil
                        ns.db.muteAlerts[eid] = next(m) and m or nil
                    end)
                oneChecks[i] = ch
            end
            ch.alertText = item.text
            local phase = item.phase ~= 1 and ("|cff3bc4b5" .. ns.PhaseLabel(item.phase) .. "|r  ") or ""
            ch.label:SetText(phase .. ns.FormatIcons(item.text) .. (item.count > 1 and ("  |cff808080x" .. item.count .. "|r") or ""))
            ch:Show()
            ch:GetScript("OnShow")(ch)
        end
        for i = #oneItems + 1, #oneChecks do oneChecks[i]:Hide() end
        oneEmpty:SetShown(#oneItems == 0)
    end

    local hCalls = Header(c, "CALLS GÉNÉRIQUES (UN PAR LIGNE)")
    local callsInfo = Muted(c, "Ils complètent les calls du boss sur la barre (8 boutons). Écris-les en anglais : ils partent tels quels en alerte raid.")
    local rebuild = Debounced(0.5, function()
        ns.PrepareCalls(ns.selectedEncounter or 0)
        if pages.raid then pages.raid.stale = true end
    end)
    local calledit = MultiLine(c, function(text)
        local list = {}
        for line in (text .. "\n"):gmatch("(.-)\r?\n") do
            line = strtrim(line)
            if line ~= "" then list[#list + 1] = line end
        end
        db.calls = list
        rebuild()
    end)
    calledit.edit:SetText(table.concat(db.calls, "\n"))

    page.layout = function(width)
        local y = -12
        y = PlaceHeader(hWindows, y)
        for _, ch in ipairs(windowChecks) do y = PlaceCheck(ch, y, width) end
        y = PlaceHeader(hAlerts, y - 12)
        for _, ch in ipairs(checks) do y = PlaceCheck(ch, y, width) end
        y = y - 8
        for _, s in ipairs(steppers) do
            s:ClearAllPoints()
            s:SetPoint("TOPLEFT", M, y)
            y = y - 30
        end
        y = Grid(actions, y - 4, width, 150) - 16
        y = PlaceHeader(hKinds, y)
        local colW = (width - GAP) / 2
        for i = 1, #kindChecks, 2 do
            local y1 = PlaceCheck(kindChecks[i], y, colW)
            local y2 = kindChecks[i + 1] and PlaceCheck(kindChecks[i + 1], y, colW, M + colW + GAP) or y1
            y = math.min(y1, y2)
        end
        y = PlaceText(kindsInfo, y - 4, width) - 16
        y = PlaceHeader(hOne, y)
        y = Place(oneBoss, y, width, 26) - 8
        if #oneItems == 0 then
            y = PlaceText(oneEmpty, y, width) - 16
        else
            y = Grid(oneAll, y, width, 120) - 6
            for i = 1, #oneItems do y = PlaceCheck(oneChecks[i], y, width) end
            y = y - 14
        end
        y = PlaceHeader(hCalls, y)
        y = PlaceText(callsInfo, y, width) - 8
        calledit:ClearAllPoints()
        calledit:SetPoint("TOPLEFT", M, y)
        calledit:Resize(width, 150)
        return y - 150
    end
end

----------------------------------------------------------------------
-- Fenêtre
----------------------------------------------------------------------

local function SelectTab(key)
    for k, page in pairs(pages) do
        page.scroll:SetShown(k == key)
        local t = tabs[k]
        t.text:SetTextColor(k == key and 1 or 0.6, k == key and 1 or 0.6, k == key and 1 or 0.65)
        t.underline:SetShown(k == key)
    end
    currentPage = pages[key]
    ShowPage(currentPage)
end

local function LayoutTabs()
    local n = #tabOrder
    local tw = math.min(100, math.floor((main:GetWidth() - 2 * M - (n - 1) * 4) / n))
    for i, key in ipairs(tabOrder) do
        local t = tabs[key]
        t:ClearAllPoints()
        t:SetPoint("TOPLEFT", M + (i - 1) * (tw + 4), -40)
        t:SetSize(tw, 26)
    end
end

local function ClampSize(w, h)
    local maxW = math.min(MAX_W, math.floor(UIParent:GetWidth() - 20))
    local maxH = math.min(MAX_H, math.floor(UIParent:GetHeight() - 20))
    return math.max(MIN_W, math.min(maxW, w)), math.max(MIN_H, math.min(maxH, h))
end

local function SaveGeometry()
    local win = ns.db.window
    win.w, win.h = math.floor(main:GetWidth() + 0.5), math.floor(main:GetHeight() + 0.5)
    local point, _, relPoint, x, y = main:GetPoint()
    if point then win.point, win.relPoint, win.x, win.y = point, relPoint, x, y end
end

-- Pendant le redimensionnement, une seule remise en page par image affichée.
local layoutPending = false
local function OnSizeChanged()
    for _, page in pairs(pages) do page.dirty = true end
    if layoutPending then return end
    layoutPending = true
    C_Timer.After(0, function()
        layoutPending = false
        if not main:IsShown() then return end
        LayoutTabs()
        if currentPage then ShowPage(currentPage) end
    end)
end

local function CreateMain()
    local win = ns.db.window
    main = CreateFrame("Frame", "RaidToolsMainFrame", UIParent, "BackdropTemplate")
    main:SetSize(ClampSize(win.w or DEFAULT_W, win.h or DEFAULT_H))
    if win.point then
        main:SetPoint(win.point, UIParent, win.relPoint or win.point, win.x or 0, win.y or 0)
    else
        main:SetPoint("CENTER")
    end
    main:SetFrameStrata("DIALOG")
    main:SetToplevel(true)
    Flat(main, COLORS.bg, { 0, 0, 0, 1 })
    main:EnableMouse(true)
    main:SetMovable(true)
    main:SetResizable(true)
    if main.SetResizeBounds then
        main:SetResizeBounds(MIN_W, MIN_H, MAX_W, MAX_H)
    elseif main.SetMinResize then
        main:SetMinResize(MIN_W, MIN_H)
        main:SetMaxResize(MAX_W, MAX_H)
    end
    if main.SetDontSavePosition then main:SetDontSavePosition(true) end
    main:SetClampedToScreen(true)
    main:RegisterForDrag("LeftButton")
    main:SetScript("OnDragStart", main.StartMoving)
    main:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SaveGeometry()
    end)
    tinsert(UISpecialFrames, "RaidToolsMainFrame")

    local accentBar = main:CreateTexture(nil, "ARTWORK")
    accentBar:SetColorTexture(A[1], A[2], A[3], 1)
    accentBar:SetPoint("TOPLEFT", 1, -1)
    accentBar:SetPoint("TOPRIGHT", -1, -1)
    accentBar:SetHeight(2)

    local title = main:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -14)
    title:SetText("|cff3bc4b5Raid|r|cffffffffTools|r")
    local sub = Muted(main, "v" .. ns.version)
    sub:SetPoint("LEFT", title, "RIGHT", 8, -1)

    local close = CreateFrame("Button", nil, main)
    close:SetSize(24, 24)
    close:SetPoint("TOPRIGHT", -8, -8)
    close.text = close:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    close.text:SetPoint("CENTER")
    close.text:SetText("×")
    close.text:SetTextColor(0.7, 0.7, 0.7)
    close:SetScript("OnEnter", function(self) self.text:SetTextColor(1, 0.4, 0.4) end)
    close:SetScript("OnLeave", function(self) self.text:SetTextColor(0.7, 0.7, 0.7) end)
    close:SetScript("OnClick", function() main:Hide() end)

    -- Poignée en bas à droite : glisser pour redimensionner, clic droit pour la taille d'origine.
    local grip = CreateFrame("Button", nil, main)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", -2, 2)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    grip:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" then main:StartSizing("BOTTOMRIGHT") end
    end)
    grip:SetScript("OnMouseUp", function(_, button)
        main:StopMovingOrSizing()
        if button == "RightButton" then main:SetSize(ClampSize(DEFAULT_W, DEFAULT_H)) end
        SaveGeometry()
    end)
    grip:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Redimensionner")
        GameTooltip:AddLine("Glisser pour changer la taille, clic droit pour revenir à la taille d'origine.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    grip:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local tabDefs = { { "raid", "Raid", BuildRaidPage }, { "reminders", "Rappels", BuildRemindersPage },
        { "tools", "Outils", BuildToolsPage }, { "pulls", "Pulls", BuildPullsPage }, { "options", "Options", BuildOptionsPage } }
    for _, def in ipairs(tabDefs) do
        local key, label = def[1], def[2]
        local t = CreateFrame("Button", nil, main)
        t.text = t:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        t.text:SetPoint("CENTER")
        t.text:SetText(label)
        t.underline = t:CreateTexture(nil, "ARTWORK")
        t.underline:SetColorTexture(A[1], A[2], A[3], 1)
        t.underline:SetPoint("BOTTOMLEFT", 10, 0)
        t.underline:SetPoint("BOTTOMRIGHT", -10, 0)
        t.underline:SetHeight(2)
        t:SetScript("OnClick", function() SelectTab(key) end)
        tabs[key] = t
        tabOrder[#tabOrder + 1] = key

        local sf = CreateFrame("ScrollFrame", nil, main, "UIPanelScrollFrameTemplate")
        sf:SetPoint("TOPLEFT", 0, -TOP)
        sf:SetPoint("BOTTOMRIGHT", -SCROLLBAR, BOTTOM)
        sf.scrollBarHideable = true
        local content = CreateFrame("Frame", nil, sf)
        content:SetSize(1, 1)
        sf:SetScrollChild(content)
        local page = { key = key, scroll = sf, content = content, stale = true, dirty = true }
        pages[key] = page
        def[3](page)
    end
    local sep = main:CreateTexture(nil, "ARTWORK")
    sep:SetColorTexture(1, 1, 1, 0.06)
    sep:SetHeight(1)
    sep:SetPoint("TOPLEFT", 1, -67)
    sep:SetPoint("TOPRIGHT", -1, -67)

    main:SetScript("OnSizeChanged", OnSizeChanged)
    main:SetScript("OnShow", function()
        if currentPage then ShowPage(currentPage) end
    end)
    main:SetScript("OnHide", function(self)
        self:StopMovingOrSizing()
    end)
    LayoutTabs()
    SelectTab("raid")
end

-- Les données ont changé : l'onglet affiché est mis à jour tout de suite, les autres à leur affichage.
function ns.RefreshUI()
    if not main then return end
    for _, page in pairs(pages) do page.stale = true end
    if main:IsShown() and currentPage then ShowPage(currentPage) end
end

function ns.ToggleUI()
    if not main then
        CreateMain()
        return
    end
    main:SetShown(not main:IsShown())
end
