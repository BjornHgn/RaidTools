-- RaidTools : outils de préparation du lead PU.
--   Vérif raid : nourriture, flacon, rune et buffs de raid, résultat posté dans le chat raid.
--   Barre de marqueurs : marqueurs de cible et marqueurs au sol en un clic.
--   Invitation auto : quiconque te chuchote le mot-clé est invité (le groupe passe en raid).
--   Rez de combat : charges partagées du raid pendant le boss (affichées dans le suivi de phase).
--   Assist auto, journal de combat automatique en raid, répartition du raid en deux moitiés équilibrées.
-- Ce qui part dans le chat raid est en anglais.

local _, ns = ...

local issecret = issecretvalue or function() return false end

----------------------------------------------------------------------
-- Vérif raid
----------------------------------------------------------------------

-- Icônes des buffs « Bien nourri ».
local FOOD_ICONS = { [136000] = true, [132805] = true, [133950] = true }

-- Flacons de Midnight, et ceux de The War Within qui marchent encore.
local FLASKS = {
    [1236763] = true, [1239355] = true, [1235057] = true, [1239755] = true,
    [1236767] = true, [1235111] = true, [1235110] = true, [1235108] = true,
    [432021] = true, [432473] = true, [431971] = true, [431972] = true, [431974] = true, [431973] = true,
}

-- Runes d'augmentation (Midnight et précédentes).
local RUNES = {
    [1234969] = true, [1242347] = true, [1264426] = true, [453250] = true, [393438] = true,
    [367405] = true, [347901] = true, [317065] = true, [270058] = true, [224001] = true,
}

-- Buffs de raid : vérifiés seulement si une classe qui les donne est dans le raid.
local BUFFS = {
    { class = "MAGE", name = "Arcane Intellect", ids = { [1459] = true } },
    { class = "PRIEST", name = "Fortitude", ids = { [21562] = true } },
    { class = "WARRIOR", name = "Battle Shout", ids = { [6673] = true } },
    { class = "DRUID", name = "Mark of the Wild", ids = { [1126] = true } },
    { class = "SHAMAN", name = "Skyfury", ids = { [462854] = true } },
    { class = "EVOKER", name = "Blessing of the Bronze", ids = {
        [381732] = true, [381741] = true, [381746] = true, [381748] = true, [381749] = true, [381750] = true,
        [381751] = true, [381752] = true, [381753] = true, [381754] = true, [381756] = true, [381757] = true,
        [381758] = true,
    } },
}

-- Joueurs qui comptent : en mythique les groupes 1 à 4, en normal / héroïque 1 à 6 (les suivants sont sur le banc).
local function Roster()
    local list = {}
    if IsInRaid() then
        local diff = select(3, GetInstanceInfo())
        local maxGroup = (diff == 16) and 4 or ((diff == 14 or diff == 15 or diff == 17) and 6 or 8)
        for i = 1, GetNumGroupMembers() do
            local name, _, subgroup, _, _, classFile, _, online = GetRaidRosterInfo(i)
            if name and subgroup and subgroup <= maxGroup then
                list[#list + 1] = { unit = "raid" .. i, name = Ambiguate(name, "short"), class = classFile, online = online,
                    group = subgroup }
            end
        end
    else
        for _, unit in ipairs({ "player", "party1", "party2", "party3", "party4" }) do
            if UnitExists(unit) then
                list[#list + 1] = { unit = unit, name = UnitName(unit), class = select(2, UnitClass(unit)),
                    online = UnitIsConnected(unit), group = 1 }
            end
        end
    end
    return list
end

local function ScanUnit(unit)
    local r = { buffs = {} }
    for i = 1, 60 do
        local a = C_UnitAuras.GetAuraDataByIndex(unit, i, "HELPFUL")
        if not a then break end
        local id, icon = a.spellId, a.icon
        if id and not issecret(id) then
            if FLASKS[id] then r.flask = true end
            if RUNES[id] then r.rune = true end
            for bi, b in ipairs(BUFFS) do
                if b.ids[id] then r.buffs[bi] = true end
            end
        end
        if icon and not issecret(icon) and FOOD_ICONS[icon] then r.food = true end
    end
    return r
end

-- Ajoute « Libellé : A, B, C » en coupant avant la limite de 255 caractères du chat.
local function AddList(lines, label, names)
    if #names == 0 then return end
    local line = label .. ": "
    for i, n in ipairs(names) do
        if #line + #n > 240 then
            lines[#lines + 1] = line:gsub(", $", "")
            line = label .. " (cont.): "
        end
        line = line .. n .. (i < #names and ", " or "")
    end
    lines[#lines + 1] = line
end

ns.RAID_BUFFS = BUFFS

-- Scan du raid, partagé par la fenêtre de vérif et le message du chat raid.
-- Renvoie nil si les buffs sont masqués (combat). m.checked = false : hors ligne ou trop loin.
function ns.ScanRaid()
    if InCombatLockdown() or (C_Secrets and C_Secrets.ShouldAurasBeSecret and C_Secrets.ShouldAurasBeSecret()) then
        return nil
    end
    local scan = { members = Roster(), classes = {}, checked = 0, food = 0, flask = 0, rune = 0 }
    for _, m in ipairs(scan.members) do
        if m.class and m.online then scan.classes[m.class] = true end
    end
    for _, m in ipairs(scan.members) do
        m.online = m.online and UnitIsConnected(m.unit) and true or false
        m.checked = m.online and UnitIsVisible(m.unit) and true or false
        if m.checked then
            local r = ScanUnit(m.unit)
            m.food, m.flask, m.rune, m.buffs = r.food, r.flask, r.rune, r.buffs
            scan.checked = scan.checked + 1
            if r.food then scan.food = scan.food + 1 end
            if r.flask then scan.flask = scan.flask + 1 end
            if r.rune then scan.rune = scan.rune + 1 end
        end
    end
    return scan
end

-- Poste les manques dans le chat raid. Uniquement à la main (bouton « Poster au raid ») : jamais automatique.
function ns.RaidCheck()
    if not IsInGroup() then
        ns.Print("Tu n'es pas en groupe.")
        return
    end
    local scan = ns.ScanRaid()
    if not scan then
        ns.Print("Vérif raid impossible en combat : le jeu masque les buffs des joueurs.")
        return
    end

    local noFood, noFlask, noRune, far, missing = {}, {}, {}, {}, {}
    for bi in ipairs(BUFFS) do missing[bi] = {} end
    for _, m in ipairs(scan.members) do
        if not m.online then
            far[#far + 1] = m.name .. " (hors ligne)"
        elseif not m.checked then
            far[#far + 1] = m.name
        else
            if not m.food then noFood[#noFood + 1] = m.name end
            if not m.flask then noFlask[#noFlask + 1] = m.name end
            if not m.rune then noRune[#noRune + 1] = m.name end
            for bi, b in ipairs(BUFFS) do
                if scan.classes[b.class] and not m.buffs[bi] then table.insert(missing[bi], m.name) end
            end
        end
    end

    local lines = {
        ("RaidTools · Raid check: food %d/%d, flask %d/%d, rune %d/%d"):format(
            scan.food, scan.checked, scan.flask, scan.checked, scan.rune, scan.checked),
    }
    AddList(lines, "No food", noFood)
    AddList(lines, "No flask", noFlask)
    for bi, b in ipairs(BUFFS) do
        AddList(lines, "Missing " .. b.name, missing[bi])
    end
    if #lines == 1 then lines[1] = lines[1] .. ". Everyone is ready!" end

    -- Dans le chat raid pour que tout le monde le voie (chef, assistant ou petit groupe).
    local public = not IsInRaid() or ns.IsLeaderOrAssist()
    if public and not ns.Locked() then
        for i, line in ipairs(lines) do
            C_Timer.After((i - 1) * 0.3, function() ns.Announce(line, false) end)
        end
    else
        for _, line in ipairs(lines) do ns.Print(line) end
    end
    -- Les runes et les joueurs non vérifiés restent dans ton chat à toi.
    if #noRune > 0 then ns.Print("Sans rune : " .. table.concat(noRune, ", ")) end
    if #far > 0 then ns.Print("Non vérifiés (trop loin) : " .. table.concat(far, ", ")) end
end

----------------------------------------------------------------------
-- Barre de marqueurs
----------------------------------------------------------------------

-- Ordre des marqueurs au sol : carré, triangle, losange, croix, étoile, cercle, lune, crâne.
local WORLD_ICON = { 6, 4, 3, 7, 1, 2, 5, 8 }
local ICON = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_"
local CLEAR_ICON = "Interface\\Buttons\\UI-GroupLoot-Pass-Up"
local SIZE, GAP, LABEL_W = 22, 2, 34
local bar

local function Tooltip(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine(self.tip)
    if self.tip2 then GameTooltip:AddLine(self.tip2, 0.7, 0.7, 0.7) end
    GameTooltip:Show()
end

-- Boutons sécurisés : marquer passe par les commandes du jeu, utilisables même en combat.
local function MarkerButton(name, texture, x, y)
    local b = CreateFrame("Button", name, bar, "SecureActionButtonTemplate")
    b:SetSize(SIZE, SIZE)
    b:SetPoint("TOPLEFT", x, y)
    -- Un seul déclenchement par clic : avec appui + relâchement, le sol se marquait puis s'annulait.
    ns.RegisterSecureClicks(b)
    local t = b:CreateTexture(nil, "ARTWORK")
    t:SetPoint("TOPLEFT", 2, -2)
    t:SetPoint("BOTTOMRIGHT", -2, 2)
    t:SetTexture(texture)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.15)
    b:SetScript("OnEnter", Tooltip)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return b
end

local function SavePosition()
    local point, _, _, x, y = bar:GetPoint()
    ns.db.markerBar.point, ns.db.markerBar.x, ns.db.markerBar.y = point, x, y
end

function ns.InitMarkerBar()
    if bar then return end
    if InCombatLockdown() then
        -- Boutons sécurisés : création reportée à la sortie du combat (rechargement en plein combat).
        local wait = CreateFrame("Frame")
        wait:RegisterEvent("PLAYER_REGEN_ENABLED")
        wait:SetScript("OnEvent", function(self)
            self:UnregisterAllEvents()
            ns.InitMarkerBar()
        end)
        return
    end
    local FLAT = "Interface\\Buttons\\WHITE8x8"
    bar = CreateFrame("Frame", "RaidToolsMarkerBar", UIParent, "BackdropTemplate")
    bar:SetSize(LABEL_W + 9 * (SIZE + GAP) + 8, 18 + 2 * (SIZE + GAP) + 6)
    bar:SetBackdrop({ bgFile = FLAT, edgeFile = FLAT, edgeSize = 1 })
    bar:SetBackdropColor(0.05, 0.05, 0.07, 0.85)
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
    local pos = ns.db.markerBar
    bar:SetPoint(pos.point or "TOP", UIParent, pos.point or "TOP", pos.x or 0, pos.y or -140)

    local title = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("TOPLEFT", 6, -4)
    title:SetText("MARQUEURS")
    title:SetTextColor(ns.accent[1], ns.accent[2], ns.accent[3])
    local hint = bar:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("LEFT", title, "RIGHT", 8, 0)
    hint:SetText("clic gauche pose, clic droit retire")
    local close = CreateFrame("Button", nil, bar)
    close:SetSize(16, 16)
    close:SetPoint("TOPRIGHT", -2, -1)
    close.text = close:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    close.text:SetPoint("CENTER")
    close.text:SetText("×")
    close:SetScript("OnClick", function() ns.ToggleMarkerBar(false) end)

    local rowY = { -18, -18 - (SIZE + GAP) }
    for row, label in ipairs({ "Cible", "Sol" }) do
        local fs = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetPoint("TOPLEFT", 6, rowY[row] - 5)
        fs:SetText(label)
    end

    local tm = SLASH_TARGET_MARKER1 or "/tm"
    local wm, cwm = SLASH_WORLD_MARKER1 or "/wm", SLASH_CLEAR_WORLD_MARKER1 or "/cwm"
    for i = 1, 8 do
        local x = LABEL_W + (i - 1) * (SIZE + GAP)
        -- Ligne 1 : marqueur sur la cible.
        local b = MarkerButton("RaidToolsTargetMarker" .. i, ICON .. i, x, rowY[1])
        b:SetAttribute("type", "macro")
        b:SetAttribute("macrotext1", tm .. " !" .. i)
        b:SetAttribute("macrotext2", tm .. " 0")
        b.tip, b.tip2 = "Marquer la cible", "Clic droit : retirer le marqueur de la cible"
        -- Ligne 2 : marqueur au sol (clic puis vise le sol).
        local w = MarkerButton("RaidToolsWorldMarker" .. i, ICON .. WORLD_ICON[i], x, rowY[2])
        w:SetAttribute("type", "macro")
        w:SetAttribute("macrotext1", wm .. " " .. i)
        w:SetAttribute("macrotext2", cwm .. " " .. i)
        w.tip, w.tip2 = "Poser ce marqueur au sol", "Clic droit : le retirer"
    end
    local x = LABEL_W + 8 * (SIZE + GAP)
    local clearTarget = MarkerButton("RaidToolsTargetMarkerClear", CLEAR_ICON, x, rowY[1])
    clearTarget:SetAttribute("type", "macro")
    clearTarget:SetAttribute("macrotext", tm .. " 0")
    clearTarget.tip = "Retirer le marqueur de la cible"
    local clearWorld = MarkerButton("RaidToolsWorldMarkerClear", CLEAR_ICON, x, rowY[2])
    clearWorld:SetAttribute("type", "macro")
    clearWorld:SetAttribute("macrotext", cwm .. " " .. (ALL or "all"))
    clearWorld.tip = "Retirer tous les marqueurs au sol"

    bar:SetShown(ns.db.markerBar.shown and true or false)
    if ns.InitEditMode then ns.InitEditMode() end
end

-- show = nil pour basculer.
function ns.ToggleMarkerBar(show)
    if not bar then
        ns.Print("La barre de marqueurs sera prête à la sortie du combat.")
        return
    end
    if InCombatLockdown() then
        ns.Print("La barre de marqueurs ne peut pas être affichée ou masquée en combat.")
        return
    end
    if show == nil then show = not bar:IsShown() end
    bar:SetShown(show)
    ns.db.markerBar.shown = show
end

----------------------------------------------------------------------
-- Invitation automatique par chuchotement
----------------------------------------------------------------------

-- Les chuchotements ne sont écoutés que si l'option est cochée.
local inviter = CreateFrame("Frame")
function ns.UpdateInviter()
    if ns.db.autoInvite then
        inviter:RegisterEvent("CHAT_MSG_WHISPER")
    else
        inviter:UnregisterEvent("CHAT_MSG_WHISPER")
    end
end
inviter:SetScript("OnEvent", function(_, _, msg, sender)
    if not (ns.db and ns.db.autoInvite) then return end
    if issecret(msg) or issecret(sender) or type(msg) ~= "string" or type(sender) ~= "string" then return end
    local word = strlower(strtrim(ns.db.inviteKeyword or ""))
    if word == "" or strlower(strtrim(msg)) ~= word then return end
    if IsInGroup() and not ns.IsLeaderOrAssist() then return end
    if IsInRaid() and GetNumGroupMembers() >= 40 then return end
    -- Un raid PU se monte en raid tout de suite : pas de blocage à 5 joueurs.
    if IsInGroup() and not IsInRaid() and UnitIsGroupLeader("player") and not InCombatLockdown() then
        C_PartyInfo.ConvertToRaid()
    end
    C_PartyInfo.InviteUnit(sender)
end)

----------------------------------------------------------------------
-- Rez de combat
----------------------------------------------------------------------

-- Charges de rez partagées du raid (le jeu les expose sur le sort Renaissance pendant une rencontre).
-- Les valeurs peuvent être secrètes en combat : on ne fait que les afficher.
function ns.GetBattleRes()
    if not (C_Spell and C_Spell.GetSpellCharges) then return end
    local ok, info = pcall(C_Spell.GetSpellCharges, 20484)
    if not ok or type(info) ~= "table" then return end
    local ok2, empty = pcall(function() return info.maxCharges == 0 end)
    if ok2 and empty then return end
    return info
end

----------------------------------------------------------------------
-- Assist automatique
----------------------------------------------------------------------

-- Pseudos séparés par des virgules ou des espaces. Chef de raid uniquement, hors combat.
function ns.AutoAssistPass()
    if not (IsInRaid() and UnitIsGroupLeader("player")) or InCombatLockdown() then return end
    local set = {}
    for name in (ns.db.autoAssist or ""):gmatch("[^,;%s]+") do set[strlower(name)] = true end
    if not next(set) then return end
    local promote = (C_PartyInfo and C_PartyInfo.PromoteToAssistant) or PromoteToAssistant
    for i = 1, GetNumGroupMembers() do
        local name, rank = GetRaidRosterInfo(i)
        if name and rank == 0 and (set[strlower(name)] or set[strlower(Ambiguate(name, "short"))]) then
            promote("raid" .. i)
        end
    end
end

----------------------------------------------------------------------
-- Journal de combat automatique en raid (pour Warcraft Logs)
----------------------------------------------------------------------

local logger = CreateFrame("Frame")
logger:RegisterEvent("PLAYER_ENTERING_WORLD")
logger:RegisterEvent("ZONE_CHANGED_NEW_AREA")
logger:SetScript("OnEvent", function()
    if not (ns.db and ns.db.autoLog) then return end
    local _, instanceType = IsInInstance()
    if instanceType == "raid" then
        if not LoggingCombat() then
            LoggingCombat(true)
            ns.db.logStartedByUs = true
            ns.Print("journal de combat activé pour le raid.")
        end
    elseif ns.db.logStartedByUs then
        ns.db.logStartedByUs = nil
        if LoggingCombat() then
            LoggingCombat(false)
            ns.Print("journal de combat arrêté (sortie du raid).")
        end
    end
end)

----------------------------------------------------------------------
-- Répartition du raid en deux moitiés équilibrées
----------------------------------------------------------------------
-- Moitié gauche = groupes 1 à N/2, moitié droite = la suite (Mythique 20 : G1-G2 / G3-G4).
-- Tanks, soigneurs, mêlées et distances sont partagés à parts égales, pour que les assignations
-- par groupe (« Soak left @g1,g2 ») soient justes. Un déplacement par mise à jour du raid.

local MELEE_CLASS = { WARRIOR = true, ROGUE = true, DEATHKNIGHT = true, DEMONHUNTER = true, PALADIN = true, MONK = true }
local RANGED_CLASS = { MAGE = true, WARLOCK = true, PRIEST = true, EVOKER = true, HUNTER = true }
local sortState

local function MaxGroup()
    local diff = select(3, GetInstanceInfo())
    if diff == 16 then return 4 elseif diff == 14 or diff == 15 or diff == 17 then return 6 end
    return 8
end

local function ComputeTargets()
    local maxGroup = MaxGroup()
    local cats = { tank = {}, healer = {}, melee = {}, flex = {}, ranged = {} }
    local n = 0
    for i = 1, GetNumGroupMembers() do
        local name, _, subgroup, _, _, class = GetRaidRosterInfo(i)
        if name and subgroup <= maxGroup then
            n = n + 1
            local role = UnitGroupRolesAssigned("raid" .. i)
            local cat = role == "TANK" and "tank" or role == "HEALER" and "healer"
                or MELEE_CLASS[class] and "melee" or RANGED_CLASS[class] and "ranged" or "flex"
            table.insert(cats[cat], name)
        end
    end
    local groups = math.min(maxGroup, 2 * math.ceil(n / 10))
    if groups < 2 then return nil end
    local half = groups / 2
    local sides = { { cap = half * 5, list = {} }, { cap = half * 5, list = {} } }
    -- Alternance gauche / droite par catégorie, en remplissant d'abord la moitié la moins pleine.
    for _, cat in ipairs({ "tank", "healer", "melee", "ranged", "flex" }) do
        for _, name in ipairs(cats[cat]) do
            local a, b = sides[1], sides[2]
            local side = (#a.list <= #b.list and #a.list < a.cap) and a or (#b.list < b.cap and b or a)
            side.list[#side.list + 1] = name
        end
    end
    local targets = {}
    for s, side in ipairs(sides) do
        local first = (s - 1) * half + 1
        for i, name in ipairs(side.list) do
            targets[name] = first + math.floor((i - 1) / 5)
        end
    end
    return targets, groups
end

local function FinishSort()
    local groups = sortState.groups
    sortState = nil
    local half = groups / 2
    local msg = half == 1 and "Groups balanced: LEFT = G1, RIGHT = G2"
        or ("Groups balanced: LEFT = G1-G%d, RIGHT = G%d-G%d"):format(half, half + 1, groups)
    ns.Announce(msg, false)
end

-- Appelé à chaque mise à jour du raid pendant la répartition.
function ns.OnGroupSortStep()
    if not sortState then return end
    if InCombatLockdown() then
        sortState = nil
        ns.Print("Répartition des groupes interrompue par le combat.")
        return
    end
    sortState.steps = sortState.steps + 1
    if sortState.steps > 80 then
        sortState = nil
        ns.Print("Répartition des groupes arrêtée : trop de déplacements.")
        return
    end
    local index, groupOf, count = {}, {}, {}
    for i = 1, GetNumGroupMembers() do
        local name, _, subgroup = GetRaidRosterInfo(i)
        if name then
            index[name], groupOf[name] = i, subgroup
            count[subgroup] = (count[subgroup] or 0) + 1
        end
    end
    for name, target in pairs(sortState.targets) do
        local cur = groupOf[name]
        if cur and cur ~= target then
            if (count[target] or 0) < 5 then
                SetRaidSubgroup(index[name], target)
            else
                for other, g in pairs(groupOf) do
                    if g == target and sortState.targets[other] ~= target then
                        SwapRaidSubgroup(index[name], index[other])
                        break
                    end
                end
            end
            -- Si le jeu ne renvoie pas de mise à jour (déplacement refusé), on relance une fois.
            local step = sortState.steps
            C_Timer.After(2, function()
                if sortState and sortState.steps == step then ns.OnGroupSortStep() end
            end)
            return
        end
    end
    FinishSort()
end

function ns.BalanceGroups()
    if not IsInRaid() or not UnitIsGroupLeader("player") then
        ns.Print("Il faut être chef de raid pour répartir les groupes.")
        return
    end
    if InCombatLockdown() then
        ns.Print("Impossible de déplacer les joueurs en combat.")
        return
    end
    local targets, groups = ComputeTargets()
    if not targets then
        ns.Print("Pas assez de joueurs pour faire deux moitiés.")
        return
    end
    sortState = { targets = targets, groups = groups, steps = 0 }
    ns.Print("Répartition des groupes en cours…")
    ns.OnGroupSortStep()
end
