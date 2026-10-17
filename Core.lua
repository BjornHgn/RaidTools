-- RaidTools : outils de gestion de raid PU
-- Cœur de l'addon : base de données, événements, communication, commandes.

local ADDON, ns = ...
_G.RaidTools = ns

ns.prefix = "RTPU"
-- Le jeu limite chaque préfixe à 10 messages d'affilée puis 1 par seconde : on répartit sur 3 préfixes.
ns.prefixes = { "RTPU", "RTPU2", "RTPU3" }
local PREFIX_SET = { RTPU = true, RTPU2 = true, RTPU3 = true }
ns.version = "1.9.0"
ns.accent = { 0.23, 0.77, 0.71 }
ns.SEP = "\t"

local defaults = {
    alert = { point = "CENTER", x = 0, y = 200, scale = 1, sound = true, tts = true, ttsVolume = 100, ttsRate = 0 },
    reminders = { enabled = true, lead = 5, autoRaidWarning = true, countdown = 0 },
    -- Tout ce qui part au raid est en anglais : compris par tout le monde en PU.
    calls = { "STACK", "SPREAD", "SOAK", "BLOODLUST", "RAID DEFENSIVES", "STOP DPS", "SWITCH ADDS", "KITE" },
    bossCalls = true,       -- les boutons de call suivent le boss et la phase
    window = { w = 460, h = 640 },
    callBar = { point = "LEFT", x = 40, y = 0 }, -- shown absent = automatique (chef / assistant)
    autoAssist = "",        -- pseudos qui reçoivent l'assist automatiquement
    autoLog = false,        -- journal de combat automatique en raid
    callRaidWarning = true,
    pullRaidWarning = true,
    breakAnnounce = true,
    acceptShared = true,
    autoShare = true,
    showTracker = true,
    -- Rappels et suivi lancés tout seuls au pull : non par défaut, le chef fait ses calls lui-même.
    autoStart = false,
    -- Alertes coupées : par type de mécanique (tank, aoe, soak... phase, break, custom) et par boss.
    muteKinds = {},
    muteBosses = {},
    muteAlerts = {},
    callOverrides = {}, -- [encounterID][phase][bouton] = call modifié depuis la barre   -- [encounterID][texte du rappel] = true : alerte coupée une par une
    -- Réglages des fenêtres faits en mode édition (taille, opacité).
    frames = {},
    minimap = { angle = 210, hide = false },
    mrtNote = true,         -- envoyer aussi la note au format MRT (Method Raid Tools)
    bossModTimers = true,   -- barres de pull et de pause chez les joueurs DBM / BigWigs
    raidCheckOnReady = true,
    autoInvite = false,
    inviteKeyword = "inv",
    markerBar = { shown = false, point = "TOP", x = 0, y = -140 },
    postAssignments = true,
    showRaidWarnings = true,
    readyCheckReport = true,
    notes = {},       -- [encounterID] = texte (0 = tous les boss)
    encounters = {},  -- [encounterID] = nom (boss rencontrés)
    history = {},     -- derniers pulls (History.lua)
    received = {},    -- [encounterID] = { from, at } : rappels reçus du chef
}

-- Anciens calls par défaut en français -> anglais.
local CALL_MIGRATION = { ["DÉFENSIFS RAID"] = "RAID DEFENSIVES", ["SWITCH ADD"] = "SWITCH ADDS" }

local function Migrate(db)
    if (db.schema or 0) < 19 then
        for i, text in ipairs(db.calls or {}) do
            db.calls[i] = CALL_MIGRATION[text] or text
        end
        db.schema = 19
    end
end

local function CopyDefaults(src, dst)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then
                dst[k] = {}
                CopyDefaults(v, dst[k])
            elseif k ~= "calls" then
                CopyDefaults(v, dst[k])
            end
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
end

----------------------------------------------------------------------
-- Utilitaires
----------------------------------------------------------------------

function ns.Print(msg)
    print("|cff3bc4b5RaidTools|r " .. tostring(msg))
end

function ns.IsLeader()
    return UnitIsGroupLeader("player")
end

function ns.IsLeaderOrAssist()
    if not IsInGroup() then return true end
    return UnitIsGroupLeader("player") or (IsInRaid() and UnitIsGroupAssistant("player"))
end

function ns.GroupChannel()
    if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) and not IsInGroup(LE_PARTY_CATEGORY_HOME) then
        return "INSTANCE_CHAT"
    elseif IsInRaid() then
        return "RAID"
    elseif IsInGroup() then
        return "PARTY"
    end
end

local SendChat = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage

-- Midnight bloque l'envoi de messages par les addons pendant les rencontres (et parfois en combat).
function ns.Locked()
    return C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown() or false
end

-- Message dans le chat de groupe. raidWarning = true -> alerte raid si possible.
function ns.Announce(msg, raidWarning)
    local channel = ns.GroupChannel()
    if not channel or ns.Locked() then
        ns.Print(msg)
        return false
    end
    if raidWarning and IsInRaid() and ns.IsLeaderOrAssist() then
        channel = "RAID_WARNING"
        ns.lastOwnWarning = GetTime()
    end
    local ok = pcall(SendChat, msg, channel)
    if not ok then ns.Print(msg) end
    return ok
end

----------------------------------------------------------------------
-- Envoi des messages d'addon, au rythme autorisé par le jeu
----------------------------------------------------------------------

-- Quota par préfixe : 10 messages d'affilée, puis 1 par seconde. Au-delà, le jeu jette le message.
local BURST = 10
local buckets = {}
local function Bucket(prefix)
    local now = GetTime()
    local b = buckets[prefix]
    if not b then
        b = { n = BURST, t = now }
        buckets[prefix] = b
    end
    b.n = math.min(BURST, b.n + (now - b.t))
    b.t = now
    return b
end

local outbox, pumping = {}, false
local function Pump()
    pumping = false
    while outbox[1] do
        if ns.Locked() then wipe(outbox) return end
        local item, bucket = outbox[1], nil
        for _, p in ipairs(item.prefixes) do
            local b = Bucket(p)
            if b.n >= 1 then bucket, item.prefix = b, p break end
        end
        if not bucket then break end
        local ok, res = pcall(C_ChatInfo.SendAddonMessage, item.prefix, item.msg, item.channel)
        local throttled = Enum and Enum.SendAddonMessageResult and Enum.SendAddonMessageResult.AddonMessageThrottle
        if ok and throttled and res == throttled then
            bucket.n = 0 -- quota déjà entamé (par un autre addon ?) : on réessaie plus tard
        else
            bucket.n = bucket.n - 1
            table.remove(outbox, 1)
        end
    end
    if outbox[1] then
        pumping = true
        C_Timer.After(0.25, Pump)
    end
end

-- prefixes : un préfixe ou une liste. urgent = passe devant les longs envois en cours.
function ns.RawSend(prefixes, msg, channel, urgent)
    if type(prefixes) == "string" then prefixes = { prefixes } end
    local item = { prefixes = prefixes, msg = msg, channel = channel }
    if urgent then table.insert(outbox, 1, item) else outbox[#outbox + 1] = item end
    if not pumping then Pump() end
end

-- Communication entre utilisateurs de l'addon. Renvoie false si rien n'est parti.
function ns.Send(cmd, ...)
    local payload = table.concat({ cmd, ... }, ns.SEP)
    local channel = ns.GroupChannel()
    if not channel or ns.Locked() then
        -- Seul ou communication bloquée : on applique au moins localement.
        ns.OnComm(payload, ns.playerName, true)
        return false
    end
    ns.RawSend(ns.prefixes, payload, channel, true)
    return true
end

-- Pour les messages longs (partage de rappels) : à la suite, sans bloquer les messages urgents.
function ns.QueueSend(...)
    local channel = ns.GroupChannel()
    if not channel or ns.Locked() then return end
    ns.RawSend(ns.prefixes, table.concat({ ... }, ns.SEP), channel)
end

-- Découpe un texte en morceaux d'au plus 'size' octets sans couper un caractère accentué.
function ns.SplitText(text, size)
    local parts, i = {}, 1
    while i <= #text do
        local j = math.min(#text, i + size - 1)
        while j < #text and j > i and text:byte(j + 1) >= 0x80 and text:byte(j + 1) < 0xC0 do j = j - 1 end
        parts[#parts + 1] = text:sub(i, j)
        i = j + 1
    end
    if #parts == 0 then parts[1] = "" end
    return parts
end

local function SenderIsLeaderOrAssist(sender)
    if sender == ns.playerName then return true end
    if not IsInGroup() then return false end
    return UnitIsGroupLeader(sender) or (IsInRaid() and UnitIsGroupAssistant(sender))
end

----------------------------------------------------------------------
-- Infos joueur (mises en cache hors combat)
----------------------------------------------------------------------

-- Spécialisations de mêlée (IDs de spé du jeu), pour les cibles @melee / @ranged.
ns.MELEE_SPECS = {
    [250] = true, [251] = true, [252] = true, [577] = true, [581] = true, [103] = true, [104] = true,
    [255] = true, [268] = true, [269] = true, [66] = true, [70] = true, [259] = true, [260] = true,
    [261] = true, [263] = true, [71] = true, [72] = true, [73] = true,
}

function ns.UpdatePlayerInfo()
    ns.playerName = UnitName("player")
    ns.playerFullName = ns.playerName .. "-" .. (GetNormalizedRealmName() or "")
    ns.playerClass = select(2, UnitClass("player"))
    local role = UnitGroupRolesAssigned("player")
    if not role or role == "NONE" then
        local getSpec = (C_SpecializationInfo and C_SpecializationInfo.GetSpecialization) or GetSpecialization
        local getRole = (C_SpecializationInfo and C_SpecializationInfo.GetSpecializationRole) or GetSpecializationRole
        local spec = getSpec and getSpec()
        role = spec and getRole and getRole(spec) or "DAMAGER"
    end
    ns.playerRole = role
    ns.playerClassID = select(3, UnitClass("player"))
    local getSpec = (C_SpecializationInfo and C_SpecializationInfo.GetSpecialization) or GetSpecialization
    local getInfo = (C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfo) or GetSpecializationInfo
    local specIndex = getSpec and getSpec()
    ns.playerSpecID = specIndex and getInfo and getInfo(specIndex) or nil
    ns.playerPos = (role == "TANK" or ns.MELEE_SPECS[ns.playerSpecID or 0]) and "melee" or "ranged"
    local index = IsInRaid() and UnitInRaid("player")
    ns.playerGroup = index and select(3, GetRaidRosterInfo(index)) or 1
end

----------------------------------------------------------------------
-- Pull, pause, calls
----------------------------------------------------------------------

function ns.Pull(seconds)
    seconds = tonumber(seconds) or 10
    if IsInGroup() and not ns.IsLeaderOrAssist() then
        ns.Print("Il faut être chef de raid ou assistant pour lancer un pull.")
        return
    end
    C_PartyInfo.DoCountdown(seconds)
    ns.BossModTimer("pull", seconds)
    if seconds > 0 and ns.db.pullRaidWarning then
        ns.Announce(("Pull in %d s"):format(seconds), true)
    end
end

function ns.CancelPull()
    C_PartyInfo.DoCountdown(0)
    ns.BossModTimer("pull", 0)
    ns.Announce("Pull cancelled", true)
end

local breakTimers = {}


local function ClearBreakTimers()
    for _, t in ipairs(breakTimers) do t:Cancel() end
    wipe(breakTimers)
end

-- Pause basée sur l'heure serveur : identique chez tout le monde, survit à un /reload.
-- endTime = GetServerTime() de fin (0 = annulation). owner = celui qui annonce en alerte raid.
function ns.ApplyBreak(endTime, duration, owner)
    ClearBreakTimers()
    ns.StopBar("break")
    local left = endTime - GetServerTime()
    if endTime <= 0 or left <= 0 then
        if ns.db.breakTimer then
            ns.ShowAlert("Break cancelled", { color = { 1, 0.4, 0.4 } })
        end
        ns.db.breakTimer = nil
        return
    end
    duration = math.max(duration or left, left)
    ns.db.breakTimer = { endTime = endTime, duration = duration, owner = owner or nil }
    ns.StartBar("break", "Break", left, { 0.35, 0.6, 1 }, duration)
    if left > 30 then
        if not ns.db.muteKinds["break"] then ns.ShowAlert("BREAK TIME", { color = { 0.35, 0.6, 1 } }) end
    end
    for _, t in ipairs(ns.SpeakCountdown(left, 5)) do breakTimers[#breakTimers + 1] = t end
    breakTimers[#breakTimers + 1] = C_Timer.NewTimer(left, function()
        ns.db.breakTimer = nil
        if not ns.db.muteKinds["break"] then ns.ShowAlert("BREAK OVER", { sound = true, tts = "Break over" }) end
    end)
    if owner and ns.db.breakAnnounce then
        if left > 90 then
            breakTimers[#breakTimers + 1] = C_Timer.NewTimer(left - 60, function()
                ns.Announce("Break: 1 min left", true)
            end)
        end
        breakTimers[#breakTimers + 1] = C_Timer.NewTimer(left, function()
            ns.Announce("Break over, let's go!", true)
        end)
    end
end

function ns.StartBreak(minutes)
    minutes = tonumber(minutes) or 5
    if IsInGroup() and not ns.IsLeaderOrAssist() then
        ns.Print("Il faut être chef de raid ou assistant pour lancer une pause.")
        return
    end
    local seconds = math.floor(minutes * 60)
    local endTime = GetServerTime() + seconds
    if ns.db.breakAnnounce then
        ns.Announce("BREAK TIME", true)
    end
    ns.ApplyBreak(endTime, seconds, true)
    ns.Send("BREAK", endTime, seconds)
    ns.BossModTimer("break", seconds)
end

function ns.CancelBreak()
    if ns.db.breakAnnounce then ns.Announce("Break cancelled", true) end
    ns.ApplyBreak(0)
    ns.Send("BREAK", 0, 0)
    ns.BossModTimer("break", 0)
end

-- Demande la pause en cours aux autres (après avoir rejoint le groupe).
function ns.RequestBreakSync()
    if ns.Locked() then
        ns.breakSyncPending = true
        return
    end
    ns.breakSyncPending = nil
    ns.Send("BREAKREQ")
end

-- Call en direct. viaMacro = l'alerte raid est déjà partie par le bouton sécurisé (/rw).
function ns.Call(text, viaMacro)
    text = text and strtrim(text) or ""
    if text == "" then return end
    if not viaMacro and ns.db.callRaidWarning then
        if ns.Locked() then
            ns.Print("Alerte raid bloquée par le jeu pendant la rencontre : utilise les boutons de call ou leurs raccourcis.")
        else
            ns.Announce(text, true)
        end
    end
    ns.lastOwnWarning = GetTime()
    ns.ShowAlert(text, { sound = true, tts = text })
    ns.Send("CALL", text)
end

----------------------------------------------------------------------
-- Réception des messages d'addon
----------------------------------------------------------------------

local incomingNotes = {}

function ns.OnComm(payload, sender, isLocal)
    local cmd, a, b, c, d = strsplit(ns.SEP, payload)
    if sender == ns.playerName and not isLocal then return end -- écho de nos propres messages
    if isLocal then return end -- l'expéditeur a déjà tout appliqué chez lui

    if cmd == "CALL" and a then
        ns.ShowAlert(a, { sound = true, tts = a })
    elseif cmd == "BREAK" then
        if SenderIsLeaderOrAssist(sender) then
            ns.ApplyBreak(tonumber(a) or 0, tonumber(b), false)
        end
    elseif cmd == "HELLO" then
        ns.Send("VER", ns.version)
    elseif cmd == "VER" then
        if ns.versionCheck then ns.versionCheck[sender] = a or "?" end
    elseif cmd == "SEL" then
        -- Le chef indique quel boss il prépare : utile pour les assignations du ready check.
        if SenderIsLeaderOrAssist(sender) and tonumber(a) then ns.selectedEncounter = tonumber(a) end
    elseif cmd == "BREAKREQ" then
        local bt = ns.db.breakTimer
        if bt and bt.owner and bt.endTime > GetServerTime() then
            ns.Send("BREAK", bt.endTime, bt.duration)
        end
    elseif cmd == "NOTE" then
        -- NOTE, encounterID, index, total, morceau
        local id, idx, total, chunk = tonumber(a), tonumber(b), tonumber(c), d or ""
        if not (id and idx and total) then return end
        if not ns.db.acceptShared or not SenderIsLeaderOrAssist(sender) then return end
        local key = sender .. ":" .. id
        local buf = incomingNotes[key]
        if not buf or idx == 1 then
            buf = { total = total, parts = {}, count = 0 }
            incomingNotes[key] = buf
        end
        if not buf.parts[idx] then
            buf.parts[idx] = chunk
            buf.count = buf.count + 1
        end
        if buf.count >= buf.total then
            incomingNotes[key] = nil
            local text = table.concat(buf.parts):gsub("\\(.)", function(ch) return ch == "n" and "\n" or ch end)
            if ns.db.notes[id] ~= text then
                ns.db.notes[id] = text ~= "" and text or nil
                ns.db.received[id] = { from = sender, at = date("%H:%M") }
                ns.Print(("Rappels reçus de %s pour %s."):format(sender, ns.EncounterName(id)))
                if ns.RefreshUI then ns.RefreshUI() end
            end
        end
    end
end

-- Partage d'une note de boss avec le raid (hors combat).
-- noMRT : ne pas toucher à la note MRT (elle ne contient qu'un boss à la fois).
function ns.ShareNote(id, silent, noMRT)
    if ns.Locked() then
        if not silent then ns.Print("Partage impossible en ce moment (communication bloquée en rencontre).") end
        return
    end
    if not IsInGroup() then
        if not silent then ns.Print("Tu n'es pas en groupe.") end
        return
    end
    -- Retours à la ligne échappés pour passer dans un message d'addon.
    local text = (ns.db.notes[id] or ""):gsub("\\", "\\\\"):gsub("\n", "\\n")
    local parts = ns.SplitText(text, 220)
    for i, part in ipairs(parts) do
        ns.QueueSend("NOTE", id, i, #parts, part)
    end
    -- Même note pour les joueurs qui ont MRT (Method Raid Tools) mais pas RaidTools.
    local mrt = ns.db.mrtNote and not noMRT and ns.SendMRTNote(id)
    if not silent then
        ns.Print(("Rappels de %s envoyés au groupe%s."):format(ns.EncounterName(id),
            mrt and " (et en note MRT)" or ""))
    end
end

-- Le chef envoie automatiquement les rappels du boss préparé au ready check / au pull,
-- avant le blocage du combat. Une note identique déjà envoyée il y a peu n'est pas renvoyée.
local lastShared = {}
function ns.AutoShare()
    if not (ns.db.autoShare and IsInRaid() and UnitIsGroupLeader("player")) then return end
    if ns.Locked() then return end
    local members = GetNumGroupMembers()
    local selected = ns.selectedEncounter or 0
    for _, id in ipairs({ selected, 0 }) do
        local text = ns.db.notes[id]
        local last = lastShared[id]
        if text and not (last and last.text == text and last.members >= members and GetTime() - last.at < 300) then
            lastShared[id] = { text = text, members = members, at = GetTime() }
            ns.ShareNote(id, true, id ~= selected)
            ns.Print(("Rappels de %s partagés avec le raid."):format(ns.EncounterName(id)))
        end
        if id == 0 then break end
    end
end

-- Crée (ou met à jour) une macro de personnage « /rw TEXTE » par bouton de call,
-- pour les poser sur tes barres d'action.
function ns.CreateCallMacros()
    if InCombatLockdown() then
        ns.Print("Impossible de créer des macros en combat.")
        return
    end
    local made = 0
    for _, text in ipairs(ns.db.calls) do
        -- 16 octets max, sans couper un caractère accentué en deux.
        local name = ("RT " .. text):sub(1, 16):gsub("[\192-\255][\128-\191]*$", function(c)
            return #c >= 2 and c or ""
        end)
        local body = "/rw " .. text
        local ok = pcall(function()
            if GetMacroIndexByName(name) > 0 then
                EditMacro(name, name, "INV_MISC_QUESTIONMARK", body)
            else
                CreateMacro(name, "INV_MISC_QUESTIONMARK", body, true)
            end
        end)
        if ok then made = made + 1 end
    end
    ns.Print(("%d macro(s) de call prêtes dans l'onglet Macros (spécifiques au personnage)."):format(made))
    if made < #ns.db.calls then
        ns.Print("Certaines macros n'ont pas pu être créées : vérifie qu'il reste de la place dans tes macros de personnage.")
    end
end

-- Assignations « rc » du boss préparé : chacun voit les siennes en grand,
-- et le chef les poste dans le chat raid pour ceux qui n'ont pas l'addon.
function ns.ShowAssignments()
    local id = ns.selectedEncounter or 0
    local _, phases = ns.ParseNote(ns.db.notes[id])
    local list = phases.assign
    if not list or #list == 0 then return end
    local mine = {}
    for _, e in ipairs(list) do
        if e.targets and ns.IsForMe(e) then mine[#mine + 1] = e.text end
    end
    if #mine > 0 then
        ns.ShowAlert(table.concat(mine, "\n", 1, math.min(3, #mine)), { color = { 0.4, 1, 0.6 }, sound = true })
        for _, t in ipairs(mine) do ns.Print("Assignation : " .. t) end
    end
    if ns.db.postAssignments and IsInRaid() and ns.IsLeader() and not ns.Locked() then
        local channel = ns.GroupChannel()
        local n = 0
        for _, e in ipairs(list) do
            if n >= 10 then break end
            local msg = "[" .. ns.EncounterNameEN(id) .. "] " .. e.text
            if e.targets then msg = msg .. ": " .. table.concat(e.targets, ", ") end
            n = n + 1
            C_Timer.After(n * 0.3, function() pcall(SendChat, msg, channel) end)
        end
    end
end

-- Qui a l'addon dans le raid ? Utile en PU pour savoir qui verra les alertes.
function ns.VersionCheck()
    if not IsInGroup() then
        ns.Print("Tu n'es pas en groupe.")
        return
    end
    if ns.Locked() then
        ns.Print("Vérification impossible pendant une rencontre.")
        return
    end
    ns.versionCheck = { [ns.playerName] = ns.version }
    ns.Send("HELLO")
    ns.Print("Vérification en cours…")
    C_Timer.After(3, function()
        local have, missing = {}, {}
        local n = GetNumGroupMembers()
        for i = 1, n do
            local unit = IsInRaid() and ("raid" .. i) or (i == n and "player" or ("party" .. i))
            local name = UnitName(unit)
            if name then
                local ver = ns.versionCheck[name]
                if ver then have[#have + 1] = name .. " (" .. ver .. ")" else missing[#missing + 1] = name end
            end
        end
        ns.Print(("|cff3bc4b5%d|r joueur(s) ont RaidTools : %s"):format(#have, table.concat(have, ", ")))
        if #missing > 0 then
            ns.Print(("|cffff6060%d|r sans l'addon : %s"):format(#missing, table.concat(missing, ", ")))
        end
        ns.lastMissing = #missing
    end)
end

-- Nom anglais (presets) pour ce qui part au raid, sinon le nom du jeu.
function ns.EncounterNameEN(id)
    id = tonumber(id) or 0
    if id == 0 then return "All bosses" end
    return (ns.Presets and ns.Presets[id] and ns.Presets[id].name) or ns.EncounterName(id)
end

function ns.EncounterName(id)
    id = tonumber(id) or 0
    if id == 0 then return "Tous les boss" end
    return ns.db.encounters[id]
        or (ns.journalEncounters and ns.journalEncounters[id])
        or (ns.Presets and ns.Presets[id] and ns.Presets[id].name)
        or ("Boss #" .. id)
end

----------------------------------------------------------------------
-- Vérification perso au ready check
----------------------------------------------------------------------

local WELL_FED_ICON = 136000

function ns.ReadyCheckReport()
    local issues = {}
    if not (C_Secrets and C_Secrets.ShouldAurasBeSecret and C_Secrets.ShouldAurasBeSecret()) then
        local fed = false
        pcall(function()
            for i = 1, 40 do
                local aura = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
                if not aura then break end
                if aura.icon == WELL_FED_ICON then fed = true break end
            end
        end)
        if not fed then issues[#issues + 1] = "Pas de buff de nourriture" end
    end
    local lowest = 1
    for slot = 1, 18 do
        local cur, max = GetInventoryItemDurability(slot)
        if cur and max and max > 0 then lowest = math.min(lowest, cur / max) end
    end
    if lowest < 0.3 then
        issues[#issues + 1] = ("Équipement à %d %% : répare"):format(lowest * 100)
    end
    if IsInRaid() then
        local index = UnitInRaid("player")
        local subgroup = index and select(3, GetRaidRosterInfo(index))
        if subgroup then ns.Print(("Tu es dans le groupe %d."):format(subgroup)) end
    end
    if #issues > 0 then
        ns.ShowAlert(table.concat(issues, "\n"), { color = { 1, 0.35, 0.35 }, sound = true })
    end
end

----------------------------------------------------------------------
-- Événements
----------------------------------------------------------------------

local f = CreateFrame("Frame")
for _, e in ipairs({
    "ADDON_LOADED", "PLAYER_LOGIN", "GROUP_ROSTER_UPDATE", "GROUP_JOINED", "PLAYER_ROLES_ASSIGNED",
    "PLAYER_SPECIALIZATION_CHANGED", "CHAT_MSG_ADDON", "ENCOUNTER_START", "ENCOUNTER_END",
    "READY_CHECK", "START_PLAYER_COUNTDOWN", "PLAYER_REGEN_ENABLED", "ADDON_RESTRICTION_STATE_CHANGED",
    "ENCOUNTER_TIMELINE_EVENT_ADDED", "CHAT_MSG_RAID_WARNING",
}) do
    pcall(f.RegisterEvent, f, e)
end

local rosterPending = false

f:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        if ... ~= ADDON then return end
        RaidToolsDB = RaidToolsDB or {}
        CopyDefaults(defaults, RaidToolsDB)
        Migrate(RaidToolsDB)
        ns.db = RaidToolsDB
        for _, p in ipairs(ns.prefixes) do C_ChatInfo.RegisterAddonMessagePrefix(p) end
    elseif event == "PLAYER_LOGIN" then
        ns.UpdatePlayerInfo()
        ns.InitAlerts()
        ns.InitTracker()
        ns.InitMinimapButton()
        ns.InitMarkerBar()
        ns.InitCallBar()
        ns.UpdateInviter()
        ns.PrepareAnnounces(ns.selectedEncounter or 0)
        local bt = ns.db.breakTimer
        if bt then ns.ApplyBreak(bt.endTime, bt.duration, bt.owner) end
        ns.Print("chargé. Tape |cff3bc4b5/rt|r pour ouvrir la fenêtre.")
    elseif event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ROLES_ASSIGNED" or event == "PLAYER_SPECIALIZATION_CHANGED" then
        -- Cet événement tombe en rafale quand le raid se remplit : une seule mise à jour par demi-seconde.
        if not rosterPending then
            rosterPending = true
            C_Timer.After(0.5, function()
                rosterPending = false
                if not InCombatLockdown() then ns.UpdatePlayerInfo() end
                ns.UpdateCallBarVisibility()
                if ns.AutoAssistPass then ns.AutoAssistPass() end
                if ns.OnGroupSortStep then ns.OnGroupSortStep() end
            end)
        end
    elseif event == "GROUP_JOINED" then
        C_Timer.After(2, ns.RequestBreakSync)
    elseif event == "ADDON_RESTRICTION_STATE_CHANGED" then
        if ns.breakSyncPending and not ns.Locked() then ns.RequestBreakSync() end
    elseif event == "PLAYER_REGEN_ENABLED" then
        -- Après un wipe : on remet les annonces au début pour le prochain pull.
        if ns.PrepareAnnounces then ns.PrepareAnnounces(ns.selectedEncounter or 0) end
    elseif event == "CHAT_MSG_ADDON" then
        local prefix, payload, _, sender = ...
        if not PREFIX_SET[prefix] then return end
        ns.OnComm(payload, Ambiguate(sender, "none"), false)
    elseif event == "READY_CHECK" then
        ns.AutoShare()
        if IsInRaid() and ns.IsLeader() and not ns.Locked() then ns.Send("SEL", ns.selectedEncounter or 0) end
        C_Timer.After(1.5, ns.ShowAssignments)
        if IsInRaid() and ns.IsLeader() and ns.PrepareAnnounces(ns.selectedEncounter or 0) then
            ns.Print(("Annonces !rw prêtes pour %s. Change de boss dans l'onglet Rappels si besoin."):format(
                ns.EncounterName(ns.selectedEncounter or 0)))
        end
        if ns.db.readyCheckReport then C_Timer.After(0.5, ns.ReadyCheckReport) end
    elseif event == "START_PLAYER_COUNTDOWN" then
        ns.AutoShare()
    elseif event == "ENCOUNTER_START" then
        local encounterID, encounterName = ...
        if encounterID and encounterName then
            ns.db.encounters[encounterID] = encounterName
        end
        ns.encounterStart = GetTime()
        -- Le boss engagé devient le boss sélectionné : barre de calls et annonces prêtes pour le prochain pull.
        if encounterID then
            ns.selectedEncounter = encounterID
            if not InCombatLockdown() then ns.PrepareAnnounces(encounterID) end
            if ns.RefreshUI then ns.RefreshUI() end
        end
        local note = ns.db.notes[encounterID]
        if IsInRaid() and ns.IsLeader() and note and note:find("!rw", 1, true) and not ns.IsPreparedFor(encounterID) then
            ns.Print("Les annonces !rw étaient préparées pour un autre boss : sélectionne ce boss dans l'onglet Rappels avant le prochain pull.")
        end
        if ns.db.autoStart then
            ns.StartReminders(encounterID)
            ns.ShowTracker()
        end
    elseif event == "ENCOUNTER_TIMELINE_EVENT_ADDED" then
        ns.OnTimelineEventAdded(...)
    elseif event == "CHAT_MSG_RAID_WARNING" then
        -- Alerte raid tapée par le chef (macro /rw, bouton de call) : on l'affiche en grand avec la voix.
        -- En rencontre le texte est une valeur secrète : on l'affiche tel quel, sans le lire ni le comparer.
        if ns.db.showRaidWarnings and GetTime() - (ns.lastOwnWarning or 0) > 1.5 then
            ns.ShowRaidWarning((...))
        end
    elseif event == "ENCOUNTER_END" then
        ns.encounterStart = nil
        ns.StopReminders()
    end
end)

----------------------------------------------------------------------
-- Commandes
----------------------------------------------------------------------

local function Help()
    ns.Print("commandes :")
    print("  /rt : ouvrir / fermer la fenêtre")
    print("  /rt pull [s] | /rt pull stop")
    print("  /rt break [min] | /rt break stop")
    print("  /rt call <texte> : call (hors rencontre ; en combat, utilise les boutons ou leurs raccourcis)")
    print("  /rt phase [n] : recale les rappels sur la phase suivante (ou n)")
    print("  /rt check : qui a l'addon dans le groupe")
    print("  /rt rc : ready check")
    print("  /rt test [encounterID] | /rt stop : simuler / arrêter les rappels")
    print("  /rt unlock | /rt lock : déplacer les alertes")
    print("  /rt verif : fenêtre de vérif raid (ready check, nourriture, flacon, rune, buffs)")
    print("  /rt marqueurs : afficher / masquer la barre de marqueurs")
    print("  /rt calls : afficher / masquer la barre de calls (calls par phase et marqueurs)")
    print("  /rt groupes : équilibrer les groupes (moitié gauche / droite)")
    print("  /rt mrt : envoyer la note du boss sélectionné aux joueurs MRT")
    print("  /rt minimap : réafficher l'icône de la minimap")
end

-- Raccourcis clavier (Options du jeu > Raccourcis > AddOns)
BINDING_HEADER_RAIDTOOLS = "RaidTools"
_G["BINDING_NAME_CLICK RaidToolsPhaseButton:LeftButton"] = "Phase suivante (alerte raid, rappels et calls)"
_G["BINDING_NAME_CLICK RaidToolsAnnounceButton:LeftButton"] = "Annoncer le prochain rappel !rw"
for i = 1, 8 do
    _G["BINDING_NAME_CLICK RaidToolsCallButton" .. i .. ":LeftButton"] = "Call " .. i .. " (suit la phase)"
end
for i, name in ipairs({ "crâne", "croix", "carré", "lune", "triangle", "losange", "cercle", "étoile" }) do
    _G["BINDING_NAME_CLICK RaidToolsMarkerCall" .. i .. ":LeftButton"] = "Call marqueur : GO TO " .. name
end

SLASH_RAIDTOOLS1 = "/rt"
SLASH_RAIDTOOLS2 = "/raidtools"
SlashCmdList.RAIDTOOLS = function(msg)
    local cmd, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
    cmd = strlower(cmd or "")
    if cmd == "" then
        ns.ToggleUI()
    elseif cmd == "pull" then
        if rest == "stop" or rest == "0" then ns.CancelPull() else ns.Pull(tonumber(rest) or 10) end
    elseif cmd == "break" or cmd == "pause" then
        if rest == "stop" or rest == "0" then ns.CancelBreak() else ns.StartBreak(tonumber(rest) or 5) end
    elseif cmd == "call" then
        ns.Call(rest)
    elseif cmd == "phase" then
        ns.SetPhase(tonumber(rest))
    elseif cmd == "phaseidx" then
        -- Envoyé par le bouton sécurisé Phase suivante : k-ième phase du boss.
        ns.SetPhaseIndex(tonumber(rest) or 2)
    elseif cmd == "check" or cmd == "version" then
        ns.VersionCheck()
    elseif cmd == "rc" then
        DoReadyCheck()
    elseif cmd == "test" then
        ns.StartReminders(tonumber(rest) or ns.selectedEncounter or 0, true)
    elseif cmd == "stop" then
        ns.StopReminders()
    elseif cmd == "minimap" then
        ns.ShowMinimapButton()
    elseif cmd == "verif" or cmd == "vérif" or cmd == "raidcheck" then
        ns.ShowRaidCheck()
    elseif cmd == "marqueurs" or cmd == "marks" or cmd == "markers" then
        ns.ToggleMarkerBar()
    elseif cmd == "calls" or cmd == "barre" then
        ns.ToggleCallBar()
    elseif cmd == "groupes" or cmd == "groups" then
        ns.BalanceGroups()
    elseif cmd == "mrt" then
        if ns.SendMRTNote(ns.selectedEncounter or 0, true) then
            ns.Print(("Note MRT de %s envoyée."):format(ns.EncounterName(ns.selectedEncounter or 0)))
        end
    elseif cmd == "unlock" then
        ns.SetAlertsLocked(false)
    elseif cmd == "lock" then
        ns.SetAlertsLocked(true)
    else
        Help()
    end
end

function RaidTools_OnAddonCompartmentClick()
    ns.ToggleUI()
end
