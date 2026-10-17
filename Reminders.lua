-- RaidTools : rappels ("customs") par boss, déclenchés au chrono depuis le début du combat.
--
-- Syntaxe d'une ligne :   1:30 Texte du rappel @cible1,cible2 !rw
--   temps   : m:ss ou secondes (ex. 1:30 ou 90)
--   @cibles : facultatif. Pseudo, tank / heal / dps, melee / ranged, classe (mage, prêtre...), groupe (g1 à g8) ou all.
--   rc Texte @cibles : assignation affichée au ready check (et postée dans le chat raid par le chef).
--             Sans cible, le rappel est pour tout le monde.
--   !rw     : le chef de raid l'annonce aussi en alerte raid (visible sans l'addon).
--   # ...   : commentaire.
--   call TEXTE / call p2 TEXTE : calls imposés pour les boutons de la barre de calls (phase 1 / phase 2).
-- Phases :
--   phase 2 2:47        début estimé de la phase 2 (depuis le pull)
--   p2 0:30 Texte       rappel 30 s après le début de la phase 2
--   En combat, /rt phase (ou le bouton Phase suivante) recale la phase sur le moment réel.
--   autophase 8 5       détection auto : 8 nouvelles barres dans la timeline Blizzard en moins de 0,3 s
--                       = changement de phase (au plus une fois toutes les 5 s).

local _, ns = ...

local ROLE_ALIASES = {
    tank = "TANK", tanks = "TANK",
    heal = "HEALER", heals = "HEALER", healer = "HEALER", healers = "HEALER", soin = "HEALER", soins = "HEALER",
    dps = "DAMAGER", dd = "DAMAGER",
}

ns.ROLE_ALIASES = ROLE_ALIASES

local CLASS_ALIASES = {
    guerrier = "WARRIOR", paladin = "PALADIN", chasseur = "HUNTER", voleur = "ROGUE", ["prêtre"] = "PRIEST",
    pretre = "PRIEST", dk = "DEATHKNIGHT", chaman = "SHAMAN", mage = "MAGE", demo = "WARLOCK", ["démoniste"] = "WARLOCK",
    moine = "MONK", druide = "DRUID", dh = "DEMONHUNTER", evoker = "EVOKER", ["évocateur"] = "EVOKER",
}

ns.CLASS_ALIASES = CLASS_ALIASES

local function ParseTime(str)
    local m, s = str:match("^(%d+):(%d%d)$")
    if m then return tonumber(m) * 60 + tonumber(s) end
    local sec = str:match("^(%d+)s?$")
    return sec and tonumber(sec)
end

-- Renvoie la liste des rappels et la table des débuts de phase estimés.
function ns.ParseNote(text)
    local list, phases = {}, { [1] = 0 }
    if not text then return list, phases end
    for line in (text .. "\n"):gmatch("(.-)\r?\n") do
        line = strtrim(line)
        if line ~= "" and not line:find("^#") and not line:find("^%-%-") then
            local callP, callText = line:match("^[cC][aA][lL][lL]%s+[pP]([%d%.]+)%s+(.+)$")
            if not callP then callText = line:match("^[cC][aA][lL][lL]%s+(.+)$") end
            local rcText = line:match("^[rR][cC]%s+(.+)$")
            local pn, pt = line:lower():match("^phase%s+([%d%.]+)%s+(%S+)$")
            local ac, ag = line:lower():match("^autophase%s+(%d+)%s*(%d*)$")
            if callText then
                local p = tonumber(callP) or 1
                phases.calls = phases.calls or {}
                phases.calls[p] = phases.calls[p] or {}
                table.insert(phases.calls[p], strtrim(callText))
            elseif rcText then
                -- Assignation affichée / annoncée au ready check : « rc Soak gauche @g1,g2 »
                local entry = {}
                local targets, raw = {}, {}
                rcText = rcText:gsub("%s*!rw", ""):gsub("%s*@(%S+)", function(group)
                    for name in group:gmatch("[^,]+") do
                        targets[#targets + 1] = strlower(name)
                        raw[#raw + 1] = name
                    end
                    return ""
                end)
                entry.text = strtrim(rcText)
                if #targets > 0 then entry.targets, entry.rawTargets = targets, raw end
                phases.assign = phases.assign or {}
                if entry.text ~= "" then table.insert(phases.assign, entry) end
            elseif pn then
                phases[tonumber(pn)] = ParseTime(pt)
            elseif ac then
                phases.auto = { count = tonumber(ac), gap = tonumber(ag) or 30 }
            else
                local phase = 1
                local p, after = line:match("^[pP]([%d%.]+)%s+(.+)$")
                if p and tonumber(p) then phase, line = tonumber(p), after end
                local ts, rest = line:match("^(%S+)%s+(.+)$")
                local t = ts and ParseTime(ts)
                if t and rest then
                    local entry = { time = t, phase = phase }
                    if rest:find("!rw", 1, true) then
                        entry.rw = true
                        rest = rest:gsub("%s*!rw", "")
                    end
                    local targets, raw = {}, {}
                    rest = rest:gsub("%s*@(%S+)", function(group)
                        for name in group:gmatch("[^,]+") do
                            targets[#targets + 1] = strlower(name)
                            raw[#raw + 1] = name -- casse d'origine (pseudos), pour la note MRT
                        end
                        return ""
                    end)
                    if #targets > 0 then entry.targets, entry.rawTargets = targets, raw end
                    entry.text = strtrim(rest)
                    if entry.text ~= "" then list[#list + 1] = entry end
                end
            end
        end
    end
    table.sort(list, function(a, b)
        if a.phase ~= b.phase then return a.phase < b.phase end
        return a.time < b.time
    end)
    return list, phases
end

function ns.IsForMe(entry)
    if not entry.targets then return true end
    local name = strlower(ns.playerName or "")
    local full = strlower(ns.playerFullName or "")
    for _, tg in ipairs(entry.targets) do
        if tg == "all" or tg == "tous" or tg == name or tg == full then return true end
        if ROLE_ALIASES[tg] and ROLE_ALIASES[tg] == ns.playerRole then return true end
        local g = tg:match("^g(%d)$")
        if g and tonumber(g) == ns.playerGroup then return true end
        if (tg == "melee" or tg == "cac") and ns.playerPos == "melee" then return true end
        if (tg == "ranged" or tg == "distance") and ns.playerPos == "ranged" then return true end
        local num = tonumber(tg)
        if num and (num == ns.playerClassID or num == ns.playerSpecID) then return true end
        local class = CLASS_ALIASES[tg] or strupper(tg)
        if class == ns.playerClass then return true end
    end
    return false
end

----------------------------------------------------------------------
-- Presets du raid actuel -> texte de note éditable
----------------------------------------------------------------------

local KIND = {
    phase  = { "Phase", rw = true },
    tank   = { "Tankbuster", "tank" },
    soak   = { "Soak", rw = true },
    adds   = { "Adds", rw = true },
    aoe    = { "AoE" },
    spread = { "Spread", "heal,dps" },
    frontal = { "Frontal" },
    knock  = { "Knockback" },
    absorb = { "Absorb", "heal" },
    debuff = { "Debuff" },
}

-- Type d'alerte d'une ligne de rappel : « Soak : Throw Junk » -> soak ; ligne perso -> custom.
local KIND_OF_LABEL = { tankbuster = "tank", knockback = "knock" }
function ns.AlertKind(text)
    local label = tostring(text):match("^(%a+) : ")
    label = label and strlower(label)
    label = label and (KIND_OF_LABEL[label] or label)
    return (label and KIND[label]) and label or "custom"
end

-- Alertes distinctes d'un boss (une entrée par texte de rappel, dans l'ordre d'apparition), pour les options.
function ns.ListAlerts(id)
    id = tonumber(id) or 0
    local entries = ns.ParseNote(ns.db.notes[id])
    if id ~= 0 then
        for _, e in ipairs((ns.ParseNote(ns.db.notes[0]))) do entries[#entries + 1] = e end
    end
    local list, byText = {}, {}
    for _, e in ipairs(entries) do
        local item = byText[e.text]
        if item then
            item.count = item.count + 1
        else
            item = { text = e.text, count = 1, phase = e.phase }
            byText[e.text] = item
            list[#list + 1] = item
        end
    end
    return list
end

-- Seuils de détection auto des phases (rafale de barres dans la timeline Blizzard).
local AUTO_PHASE = {
    [3445] = "autophase 8 5",   -- Entombed Sentinels
    [3497] = "autophase 4 50",  -- The Lost Explorers
}

function ns.AutoPhaseLine(id) return AUTO_PHASE[id] end

local function FormatTime(t)
    return ("%d:%02d"):format(math.floor(t / 60), t % 60)
end


function ns.HasPreset(id, diff)
    return ns.Presets and ns.Presets[id] and ns.Presets[id][diff] and true or false
end

-- kinds : table { aoe = true, ... } des types à inclure (nil = tous)
function ns.BuildPresetNote(id, diff, kinds)
    local preset = ns.Presets[id]
    local data = preset and preset[diff]
    if not data then return end

    -- Regroupe les sorts d'un même type lancés à la même seconde (variantes d'une même mécanique).
    local lines, index = {}, {}
    for _, a in ipairs(data) do
        local kind, spellID, name, phase, times = a[1], a[2], a[3], a[4], a[5]
        if not kinds or kinds[kind] then
            for _, t in ipairs(times) do
                local key = phase .. ":" .. t .. ":" .. kind
                local l = index[key]
                if l then
                    if #l.names < 2 then l.names[#l.names + 1] = name end
                else
                    -- Nom anglais des données : les lignes !rw partent en alerte raid, en anglais pour tout le PU.
                    l = { phase = phase, time = t, kind = kind, names = { name } }
                    index[key] = l
                    lines[#lines + 1] = l
                end
            end
        end
    end
    table.sort(lines, function(a, b)
        if a.phase ~= b.phase then return a.phase < b.phase end
        return a.time < b.time
    end)

    local diffName = diff == 16 and "Mythique" or "Héroïque"
    local out = {
        ("# Preset %s (%s), à adapter à ton raid"):format(preset.name, diffName),
        "# Temps relevés sur des kills : un pull plus lent ou plus rapide décale les phases.",
        "# !rw = annoncé en alerte raid pour ceux qui n'ont pas l'addon (touche Annonce du chef).",
    }
    if #data.phases > 0 then
        out[#out + 1] = "# Débuts de phase estimés. En combat : /rt phase pour recaler."
        if AUTO_PHASE[id] then
            out[#out + 1] = "# Détection auto des phases (à surveiller les premiers essais) :"
            out[#out + 1] = AUTO_PHASE[id]
        end
        for _, p in ipairs(data.phases) do
            out[#out + 1] = ("phase %s %s"):format(tostring(p[1]), FormatTime(p[2]))
        end
    end
    -- En-têtes de section bien visibles pour chaque phase.
    local estimate = {}
    for _, p in ipairs(data.phases) do estimate[p[1]] = p[2] end
    local lastPhase
    for _, l in ipairs(lines) do
        if l.phase ~= lastPhase then
            out[#out + 1] = ""
            if l.phase == 1 then
                out[#out + 1] = "# ===== PHASE 1 · dès le pull ====="
            else
                out[#out + 1] = ("# ===== PHASE %s · début estimé %s ====="):format(tostring(l.phase),
                    estimate[l.phase] and FormatTime(estimate[l.phase]) or "?")
            end
            lastPhase = l.phase
        end
        local k = KIND[l.kind]
        local txt = k[1] .. " : " .. table.concat(l.names, " / ")
        if k[2] then txt = txt .. " @" .. k[2] end
        if k.rw then txt = txt .. " !rw" end
        local prefix = l.phase ~= 1 and ("p" .. tostring(l.phase) .. " ") or ""
        out[#out + 1] = prefix .. FormatTime(l.time) .. " " .. txt
    end
    return table.concat(out, "\n")
end

----------------------------------------------------------------------
-- Programmation pendant la rencontre
----------------------------------------------------------------------

local run -- état de la rencontre en cours

local function CancelPhase(phase)
    local list = run and run.timers[phase]
    if not list then return end
    for _, t in ipairs(list) do t:Cancel() end
    run.timers[phase] = nil
    run.starts[phase] = nil
    run.mine = nil -- liste du suivi à refaire
    ns.StopAllBars("rem" .. phase .. "_")
end

function ns.StopReminders()
    if run then
        for phase in pairs(run.timers) do CancelPhase(phase) end
    end
    run = nil
    ns.StopAllBars("rem")
end

-- Programme tous les rappels d'une phase qui commence à 'start' secondes après le pull.
local function SchedulePhase(phase, start)
    CancelPhase(phase)
    local list = {}
    run.timers[phase] = list
    run.starts[phase] = start
    run.mine = nil
    local elapsed = GetTime() - run.pullTime
    local lead = ns.db.reminders.lead

    local function At(delay, fn)
        if delay < -0.5 then return end
        if delay <= 0 then fn() else list[#list + 1] = C_Timer.NewTimer(delay, fn) end
    end

    for i, e in ipairs(run.entries) do
        if e.phase == phase then
            local fireAt = start + e.time - elapsed
            if e.mine then
                local barId = "rem" .. phase .. "_" .. i
                local showAt = math.max(0, fireAt - lead)
                if fireAt > 0 then
                    At(showAt, function() ns.StartBar(barId, e.text, fireAt - showAt) end)
                end
                At(fireAt, function() ns.ShowAlert(e.text, { sound = true, tts = e.text }) end)
                local cd = ns.db.reminders.countdown or 0
                if cd > 0 then
                    for n = cd, 1, -1 do
                        At(fireAt - n, function() ns.Speak(tostring(n)) end)
                    end
                end
            end
            if run.announcer and e.rw then
                local msg = e.text
                if e.targets then msg = msg .. " (" .. table.concat(e.targets, ", ") .. ")" end
                At(fireAt, function()
                    -- En rencontre le jeu bloque l'envoi automatique : on guide le chef vers sa touche
                    -- d'annonce, qui enverra ce message en alerte raid pour tout le monde.
                    if run and run.prepared then
                        ns.PromptAnnounce(msg)
                    elseif not ns.Locked() then
                        ns.Announce(msg, true)
                    end
                end)
            end
        end
    end
end

-- isTest : simulation hors combat (aucune alerte raid n'est envoyée).
function ns.StartReminders(encounterID, isTest)
    ns.StopReminders()
    if not ns.db.reminders.enabled then return end
    encounterID = tonumber(encounterID) or 0

    local entries, phases = ns.ParseNote(ns.db.notes[encounterID])
    if encounterID ~= 0 then
        for _, e in ipairs((ns.ParseNote(ns.db.notes[0]))) do entries[#entries + 1] = e end
    end
    if #entries == 0 then
        if isTest then ns.Print(("Aucun rappel pour %s."):format(ns.EncounterName(encounterID))) end
        return
    end
    -- Ciblage calculé une fois par rencontre (rôle, groupe et classe ne changent pas en combat).
    -- Alertes coupées (type de mécanique ou boss entier) : ni alerte, ni barre, ni suivi chez toi.
    -- Les annonces !rw du chef pour le raid ne sont pas concernées.
    local bossMuted = ns.db.muteBosses[encounterID]
    local lineMuted = ns.db.muteAlerts[encounterID] or {}
    for _, e in ipairs(entries) do
        e.mine = ns.IsForMe(e) and not bossMuted and not lineMuted[e.text] and not ns.db.muteKinds[ns.AlertKind(e.text)]
    end

    run = {
        entries = entries,
        estimates = phases,
        auto = phases.auto,
        burst = {},
        lastPhaseAt = GetTime(),
        timers = {},
        starts = {},
        pullTime = GetTime(),
        phase = 1,
        announcer = not isTest and ns.db.reminders.autoRaidWarning and IsInRaid() and ns.IsLeader(),
        prepared = ns.IsPreparedFor and ns.IsPreparedFor(encounterID),
    }
    local scheduled = {}
    for _, e in ipairs(entries) do
        if not scheduled[e.phase] then
            scheduled[e.phase] = true
            local start = (e.phase == 1) and 0 or phases[e.phase]
            if start then SchedulePhase(e.phase, start) end
        end
    end

    if ns.ShowTracker then ns.ShowTracker() end
    if isTest then
        ns.Print(("Test des rappels de %s lancé (%d rappel(s)). |cff3bc4b5/rt stop|r pour arrêter."):format(
            ns.EncounterName(encounterID), #entries))
    end
end

-- Liste triée des phases connues de la rencontre en cours.
local function PhaseList()
    local seen, list = {}, {}
    for _, e in ipairs(run.entries) do
        if not seen[e.phase] then seen[e.phase] = true; list[#list + 1] = e.phase end
    end
    for p in pairs(run.estimates) do
        if type(p) == "number" and not seen[p] then seen[p] = true; list[#list + 1] = p end
    end
    -- Mêmes phases que la barre de calls (lignes « call pN »), pour que la touche Phase reste alignée.
    for p in pairs(run.estimates.calls or {}) do
        if not seen[p] then seen[p] = true; list[#list + 1] = p end
    end
    table.sort(list)
    return list
end

-- Recale une phase (et les suivantes) sur le moment présent.
-- fromAuto : détectée par l'addon (timeline Blizzard), sans action du chef.
function ns.SetPhase(phase, fromAuto)
    if not run then
        ns.Print("Aucune rencontre en cours.")
        return
    end
    local list = PhaseList()
    run.lastPhaseAt = GetTime()
    wipe(run.burst)
    if not phase then
        for _, p in ipairs(list) do
            if p > run.phase then phase = p break end
        end
        if not phase then return end
    end
    local now = GetTime() - run.pullTime
    local est = run.estimates[phase]
    local delta = est and (now - est) or 0
    run.phase = phase
    for _, p in ipairs(list) do
        if p < phase then
            CancelPhase(p) -- les mécaniques de la phase précédente ne reviendront pas
        elseif p == phase then
            SchedulePhase(p, now)
        elseif p > phase and run.estimates[p] then
            SchedulePhase(p, run.estimates[p] + delta)
        end
    end
    local label = ns.PhaseLabel(phase)
    if not ns.db.muteKinds.phase then ns.ShowAlert(label, { color = ns.accent, sound = true, tts = label }) end
    -- Boutons de call de la nouvelle phase : direct hors combat, sinon on guide le chef vers sa touche Phase.
    local k
    for i, p in ipairs(list) do
        if p == phase then k = i end
    end
    if k and not (ns.SyncCallPhase and ns.SyncCallPhase(k)) and fromAuto and ns.PromptPhaseKey then
        ns.PromptPhaseKey(phase)
    end
end

-- Appelé par le bouton sécurisé Phase suivante (« /rt phaseidx k ») : k-ième phase de la note.
-- Si l'addon a déjà détecté cette phase (ou une plus loin), on ne recale rien.
function ns.SetPhaseIndex(k)
    local phase = run and PhaseList()[k]
    if not phase then
        local label = ns.PlanPhaseLabel and ns.PlanPhaseLabel(k) or ("PHASE " .. k)
        if not ns.db.muteKinds.phase then ns.ShowAlert(label, { color = ns.accent, sound = true, tts = label }) end
        if ns.RefreshCallBar then ns.RefreshCallBar() end
        return
    end
    if phase <= run.phase then
        if ns.RefreshCallBar then ns.RefreshCallBar() end
        return
    end
    ns.SetPhase(phase)
end

-- Appelé à chaque ENCOUNTER_TIMELINE_EVENT_ADDED : Blizzard ajoute d'un coup les barres
-- de la nouvelle phase, ce qui trahit le changement de phase.
function ns.OnTimelineEventAdded(info)
    if not (run and run.auto and info) then return end
    local src = Enum.EncounterTimelineEventSource
    if src and info.source ~= nil and info.source ~= src.Encounter then return end
    local now = GetTime()
    if now < run.lastPhaseAt + run.auto.gap then return end
    local burst = run.burst
    burst[#burst + 1] = now
    local recent = 0
    for _, t in ipairs(burst) do
        if now - t < 0.3 then recent = recent + 1 end
    end
    if recent >= run.auto.count then
        ns.SetPhase(nil, true)
    end
end

-- État de la rencontre pour l'affichage du suivi de phase :
-- phase en cours, temps écoulé dans la phase, et les prochains rappels qui me concernent.
-- Appelé plusieurs fois par seconde : la liste triée n'est refaite qu'au changement de phase,
-- et le résultat réutilise toujours les mêmes tables (pas de déchets pour le ramasse-miettes).
local info = { upcoming = { {}, {}, {} }, count = 0 }

local function RebuildMine()
    local mine = {}
    for _, e in ipairs(run.entries) do
        local start = run.starts[e.phase]
        if start and e.mine then mine[#mine + 1] = { at = start + e.time, text = e.text, phase = e.phase } end
    end
    table.sort(mine, function(a, b) return a.at < b.at end)
    run.mine, run.cursor = mine, 1
end

function ns.GetRunInfo(maxUpcoming)
    if not run then return nil end
    if not run.mine then RebuildMine() end
    local elapsed = GetTime() - run.pullTime
    local phase, phaseStart = 1, 0
    local nextPhase, nextIn
    for p, start in pairs(run.starts) do
        if start <= elapsed then
            if p >= phase then phase, phaseStart = p, start end
        elseif not nextIn or start - elapsed < nextIn then
            nextPhase, nextIn = p, start - elapsed
        end
    end
    local mine = run.mine
    while mine[run.cursor] and mine[run.cursor].at <= elapsed do run.cursor = run.cursor + 1 end
    local n = 0
    for i = run.cursor, run.cursor + math.min(maxUpcoming or 3, 3) - 1 do
        local m = mine[i]
        if not m then break end
        n = n + 1
        local u = info.upcoming[n]
        u.text, u.phase, u.inSec = m.text, m.phase, m.at - elapsed
    end
    info.count = n
    info.phase, info.inPhase, info.elapsed = phase, elapsed - phaseStart, elapsed
    info.nextPhase, info.nextIn = nextPhase, nextIn
    info.bossOnly = nil
    return info
end
