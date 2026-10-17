-- RaidTools : fenêtre « Vérif raid », qui regroupe le ready check et la vérif des buffs.
-- Une ligne par joueur : statut du ready check, nourriture, flacon, rune et buffs de raid.
-- Le bouton « Poster au raid » envoie les manques dans le chat raid, en anglais (ns.RaidCheck).
-- Les buffs ne sont relus que fenêtre ouverte, au plus deux fois par seconde.

local _, ns = ...

local FLAT = "Interface\\Buttons\\WHITE8x8"
local TEX_READY = "Interface\\RaidFrame\\ReadyCheck-Ready"
local TEX_NO = "Interface\\RaidFrame\\ReadyCheck-NotReady"
local TEX_WAIT = "Interface\\RaidFrame\\ReadyCheck-Waiting"
local ROW_H, CELL, NAME_W, PAD = 18, 26, 150, 10

local frame, summary, rows, headerCells = nil, nil, {}, {}
local columns
local readyState = {}   -- pseudo -> "ready" / "notready" / "waiting"
local refreshPending = false
local issecret = issecretvalue or function() return false end

-- Colonnes : statut du ready check, consommables, puis buffs de raid.
local function BuildColumns()
    local function Icon(spellID, fallback)
        local tex = C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(spellID)
        return tex or fallback
    end
    columns = {
        { key = "ready", tip = "Ready check", icon = TEX_READY },
        { key = "food", tip = "Nourriture", icon = 136000 },
        { key = "flask", tip = "Flacon", icon = Icon(1236763, 3566840) },
        { key = "rune", tip = "Rune d'augmentation", icon = Icon(1234969, 4644002) },
    }
    for bi, b in ipairs(ns.RAID_BUFFS) do
        local id = next(b.ids)
        columns[#columns + 1] = { key = "buff", buff = bi, tip = b.name, icon = Icon(id, 134400), class = b.class }
    end
end

local function ClassColor(class)
    local c = class and ((C_ClassColor and C_ClassColor.GetClassColor and C_ClassColor.GetClassColor(class))
        or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]))
    if c then return c.r, c.g, c.b end
    return 1, 1, 1
end

local function SetCell(tex, state)
    if state == true then
        tex:SetTexture(TEX_READY); tex:SetAlpha(1)
    elseif state == false then
        tex:SetTexture(TEX_NO); tex:SetAlpha(1)
    elseif state == "wait" then
        tex:SetTexture(TEX_WAIT); tex:SetAlpha(1)
    else
        tex:SetTexture(nil)
    end
end

local function GetRow(i)
    local row = rows[i]
    if row then return row end
    row = CreateFrame("Frame", nil, frame)
    row:SetSize(NAME_W + #columns * CELL, ROW_H)
    row:SetPoint("TOPLEFT", PAD, -62 - (i - 1) * ROW_H)
    if i % 2 == 0 then
        local bg = row:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(1, 1, 1, 0.03)
    end
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.name:SetPoint("LEFT", 2, 0)
    row.name:SetWidth(NAME_W - 4)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    row.cells = {}
    for c = 1, #columns do
        local t = row:CreateTexture(nil, "ARTWORK")
        t:SetSize(14, 14)
        t:SetPoint("LEFT", NAME_W + (c - 1) * CELL + (CELL - 14) / 2, 0)
        row.cells[c] = t
    end
    rows[i] = row
    return row
end

local function ReadyCell(name)
    local st = readyState[name]
    if st == "ready" then return true elseif st == "notready" then return false elseif st == "waiting" then return "wait" end
end

local function Refresh()
    if not (frame and frame:IsShown()) then return end
    local scan = ns.ScanRaid()
    if not scan then
        summary:SetText("|cffff6060Buffs masqués par le jeu en combat.|r")
        return
    end
    table.sort(scan.members, function(a, b)
        if a.group ~= b.group then return (a.group or 9) < (b.group or 9) end
        return a.name < b.name
    end)
    local ready, total = 0, 0
    for i, m in ipairs(scan.members) do
        local row = GetRow(i)
        local r, g, b = ClassColor(m.class)
        row.name:SetText(("|cff808080%d|r  %s%s"):format(m.group or 1, m.name,
            not m.online and " |cff808080(hors ligne)|r" or (not m.checked and " |cff808080(loin)|r" or "")))
        row.name:SetTextColor(r, g, b)
        for c, col in ipairs(columns) do
            local state
            if col.key == "ready" then
                state = ReadyCell(m.name)
            elseif m.checked then
                if col.key == "buff" then
                    if scan.classes[col.class] then state = m.buffs[col.buff] and true or false end
                else
                    state = m[col.key] and true or false
                end
            end
            SetCell(row.cells[c], state)
        end
        row:Show()
        total = total + 1
        if readyState[m.name] == "ready" then ready = ready + 1 end
    end
    for i = #scan.members + 1, #rows do rows[i]:Hide() end
    local readyText = next(readyState) and ("Prêts %d/%d  ·  "):format(ready, total) or ""
    summary:SetText(("%sNourriture %d/%d  ·  Flacon %d/%d  ·  Rune %d/%d"):format(
        readyText, scan.food, scan.checked, scan.flask, scan.checked, scan.rune, scan.checked))
    frame:SetHeight(62 + math.max(1, #scan.members) * ROW_H + 40)
end

-- Plusieurs changements d'auras d'affilée : une seule relecture par demi-seconde.
local function QueueRefresh()
    if refreshPending then return end
    refreshPending = true
    C_Timer.After(0.5, function()
        refreshPending = false
        Refresh()
    end)
end

local function Button(parent, text, w, onClick)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(w, 22)
    b:SetBackdrop({ bgFile = FLAT, edgeFile = FLAT, edgeSize = 1 })
    b:SetBackdropColor(0.12, 0.12, 0.15, 1)
    b:SetBackdropBorderColor(0.2, 0.2, 0.24, 1)
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.text:SetPoint("CENTER")
    b.text:SetText(text)
    b:SetScript("OnEnter", function(self) self:SetBackdropBorderColor(ns.accent[1], ns.accent[2], ns.accent[3], 1) end)
    b:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(0.2, 0.2, 0.24, 1) end)
    b:SetScript("OnClick", onClick)
    return b
end

local function HeaderTip(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine(self.tip)
    GameTooltip:Show()
end

local function Create()
    BuildColumns()
    local width = PAD * 2 + NAME_W + #columns * CELL
    frame = CreateFrame("Frame", "RaidToolsCheckFrame", UIParent, "BackdropTemplate")
    frame:SetSize(math.max(width, 380), 200)
    frame:SetPoint("CENTER", 0, 80)
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:SetBackdrop({ bgFile = FLAT, edgeFile = FLAT, edgeSize = 1 })
    frame:SetBackdropColor(0.05, 0.05, 0.07, 0.96)
    frame:SetBackdropBorderColor(0, 0, 0, 1)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    tinsert(UISpecialFrames, "RaidToolsCheckFrame")

    local accent = frame:CreateTexture(nil, "ARTWORK")
    accent:SetColorTexture(ns.accent[1], ns.accent[2], ns.accent[3], 1)
    accent:SetPoint("TOPLEFT", 1, -1)
    accent:SetPoint("TOPRIGHT", -1, -1)
    accent:SetHeight(2)

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", PAD, -10)
    title:SetText("VÉRIF RAID")
    title:SetTextColor(ns.accent[1], ns.accent[2], ns.accent[3])
    summary = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    summary:SetPoint("TOPLEFT", PAD, -28)
    summary:SetPoint("RIGHT", -PAD, 0)
    summary:SetJustifyH("LEFT")

    local close = CreateFrame("Button", nil, frame)
    close:SetSize(20, 20)
    close:SetPoint("TOPRIGHT", -4, -4)
    close.text = close:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    close.text:SetPoint("CENTER")
    close.text:SetText("×")
    close:SetScript("OnClick", function() frame:Hide() end)

    -- En-têtes : une icône par colonne, nom au survol.
    for c, col in ipairs(columns) do
        local h = CreateFrame("Frame", nil, frame)
        h:SetSize(CELL, 16)
        h:SetPoint("TOPLEFT", PAD + NAME_W + (c - 1) * CELL, -44)
        local t = h:CreateTexture(nil, "ARTWORK")
        t:SetSize(16, 16)
        t:SetPoint("CENTER")
        t:SetTexture(col.icon)
        h.tip = col.tip
        h:EnableMouse(true)
        h:SetScript("OnEnter", HeaderTip)
        h:SetScript("OnLeave", function() GameTooltip:Hide() end)
        headerCells[c] = h
    end
    local nameHeader = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    nameHeader:SetPoint("TOPLEFT", PAD + 2, -47)
    nameHeader:SetText("Groupe  Joueur")

    local rc = Button(frame, "Ready check", 110, function() DoReadyCheck() end)
    rc:SetPoint("BOTTOMLEFT", PAD, 10)
    local post = Button(frame, "Poster au raid", 110, function() ns.RaidCheck() end)
    post:SetPoint("LEFT", rc, "RIGHT", 6, 0)
    local refresh = Button(frame, "Actualiser", 90, Refresh)
    refresh:SetPoint("LEFT", post, "RIGHT", 6, 0)

    -- Auras et roster suivis seulement fenêtre ouverte.
    frame:SetScript("OnShow", function(self)
        self:RegisterEvent("UNIT_AURA")
        self:RegisterEvent("GROUP_ROSTER_UPDATE")
        Refresh()
    end)
    frame:SetScript("OnHide", function(self)
        self:UnregisterEvent("UNIT_AURA")
        self:UnregisterEvent("GROUP_ROSTER_UPDATE")
        self:StopMovingOrSizing()
    end)
    frame:SetScript("OnEvent", function(_, event, unit)
        if event == "UNIT_AURA" and type(unit) == "string" and not (unit:find("^raid") or unit:find("^party") or unit == "player") then
            return
        end
        QueueRefresh()
    end)
    frame:Hide()
end

function ns.ShowRaidCheck(show)
    if not frame then Create() end
    if show == nil then show = not frame:IsShown() end
    frame:SetShown(show)
    if show then Refresh() end
end

----------------------------------------------------------------------
-- Statut du ready check (suivi même fenêtre fermée : ce sont des événements rares)
----------------------------------------------------------------------

local watcher = CreateFrame("Frame")
watcher:RegisterEvent("READY_CHECK")
watcher:RegisterEvent("READY_CHECK_CONFIRM")
watcher:RegisterEvent("READY_CHECK_FINISHED")
watcher:SetScript("OnEvent", function(_, event, arg1, arg2)
    if event == "READY_CHECK" then
        wipe(readyState)
        local n = IsInRaid() and GetNumGroupMembers() or 0
        for i = 1, n do
            local name = GetRaidRosterInfo(i)
            if name then readyState[Ambiguate(name, "short")] = "waiting" end
        end
        if not IsInRaid() then
            for _, unit in ipairs({ "player", "party1", "party2", "party3", "party4" }) do
                if UnitExists(unit) then readyState[UnitName(unit)] = "waiting" end
            end
        end
        -- L'initiateur est prêt d'office.
        if type(arg1) == "string" and not issecret(arg1) then readyState[Ambiguate(arg1, "short")] = "ready" end
        -- Le chef (ou l'assistant) voit la fenêtre s'ouvrir avec le ready check.
        if ns.db.raidCheckOnReady and IsInGroup() and (not IsInRaid() or ns.IsLeaderOrAssist()) then
            ns.ShowRaidCheck(true)
        end
    elseif event == "READY_CHECK_CONFIRM" then
        if type(arg1) == "string" then
            local name = UnitName(arg1)
            if name and not issecret(name) then readyState[name] = arg2 and "ready" or "notready" end
        end
    elseif event == "READY_CHECK_FINISHED" then
        -- Ceux qui n'ont pas répondu : pas prêts (AFK).
        for name, st in pairs(readyState) do
            if st == "waiting" then readyState[name] = "notready" end
        end
    end
    QueueRefresh()
end)
