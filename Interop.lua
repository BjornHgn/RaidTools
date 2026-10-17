-- RaidTools : passerelles vers les addons que les joueurs PU ont souvent déjà.
--   DBM / BigWigs : barres de pull et de pause envoyées avec leur format de message.
--   MRT (Method Raid Tools) : la note du boss, convertie dans la syntaxe de note MRT
--   ({time:m:ss}, {time:m:ss,p2}, icônes de rôle) et envoyée par son canal de note.
-- Rien n'est repris du code de ces addons : seuls les formats de message publics sont utilisés.

local _, ns = ...

----------------------------------------------------------------------
-- DBM / BigWigs
----------------------------------------------------------------------

-- kind = "pull" ou "break", seconds = 0 pour annuler.
function ns.BossModTimer(kind, seconds)
    if not ns.db.bossModTimers or ns.Locked() then return end
    local channel = ns.GroupChannel()
    if not channel then return end
    seconds = math.max(0, math.floor(tonumber(seconds) or 0))
    ns.RawSend("BigWigs", ("P^%s^%d"):format(kind == "pull" and "Pull" or "Break", seconds), channel, true)
    local realm = (GetRealmName() or ""):gsub("[%s%-]+", "")
    local who = UnitName("player") .. "-" .. realm
    local msg
    if kind == "pull" then
        local mapID = select(8, GetInstanceInfo()) or 0
        msg = ("%s\t1\tPT\t%d\t%d"):format(who, seconds, mapID)
    else
        msg = ("%s\t1\tBT\t%d"):format(who, seconds)
    end
    ns.RawSend("D5", msg, channel, true)
end

----------------------------------------------------------------------
-- Note MRT
----------------------------------------------------------------------

-- Lignes des presets qui doublent ce que DBM / BigWigs affichent déjà : on ne les met pas
-- dans la note MRT, sauf si elles sont marquées !rw ou assignées à des joueurs / groupes.
local PRESET_LABELS = {
    tankbuster = true, aoe = true, spread = true, frontal = true, knockback = true,
    absorb = true, debuff = true, soak = true, adds = true, phase = true,
}

local MRT_ROLE_ICON = { TANK = "{tank}", HEALER = "{healer}", DAMAGER = "{dps}" }

local function FormatTime(t)
    t = math.floor(t + 0.5)
    return ("%d:%02d"):format(math.floor(t / 60), t % 60)
end

local function IsGeneric(tg)
    return tg == "all" or tg == "tous" or ns.ROLE_ALIASES[tg] ~= nil
end

local function HasSpecificTarget(e)
    for _, tg in ipairs(e.targets or {}) do
        if not IsGeneric(tg) then return true end
    end
    return false
end

-- Cibles RaidTools -> texte lisible dans MRT (les pseudos gardent leur casse : MRT les colore).
local function TargetsText(e)
    local icons, words = {}, {}
    for i, tg in ipairs(e.targets or {}) do
        local raw = e.rawTargets and e.rawTargets[i] or tg
        local role = ns.ROLE_ALIASES[tg]
        local g = tg:match("^g(%d)$")
        if role then
            icons[#icons + 1] = MRT_ROLE_ICON[role]
        elseif g then
            words[#words + 1] = "G" .. g
        elseif tg == "melee" or tg == "cac" then
            words[#words + 1] = "Melee"
        elseif tg == "ranged" or tg == "distance" then
            words[#words + 1] = "Ranged"
        elseif tg ~= "all" and tg ~= "tous" and not tonumber(tg) then
            words[#words + 1] = raw
        end
    end
    local out = table.concat(icons)
    if #words > 0 then out = out .. (out ~= "" and " " or "") .. table.concat(words, ", ") end
    return out
end

local function Clean(text)
    return (tostring(text):gsub("\t", " "))
end

local MAX_LINES = 70

-- Construit la note MRT d'un boss (en anglais : elle est lue par tout le raid). Renvoie nil s'il n'y a rien d'utile à envoyer.
function ns.BuildMRTNote(id)
    id = tonumber(id) or 0
    local entries, phases = ns.ParseNote(ns.db.notes[id])
    local assign = phases.assign or {}
    if id ~= 0 then
        local generic, gp = ns.ParseNote(ns.db.notes[0])
        for _, e in ipairs(generic) do entries[#entries + 1] = e end
        for _, a in ipairs(gp.assign or {}) do assign[#assign + 1] = a end
        table.sort(entries, function(a, b)
            if a.phase ~= b.phase then return a.phase < b.phase end
            return a.time < b.time
        end)
    end

    local kept = {}
    for _, e in ipairs(entries) do
        local label = e.text:match("^(%a+) : ")
        if e.rw or HasSpecificTarget(e) or not (label and PRESET_LABELS[strlower(label)]) then
            kept[#kept + 1] = e
        end
    end
    if #kept == 0 and #assign == 0 then return nil end

    local out = { "|cff3bc4b5RaidTools|r - " .. Clean(ns.EncounterNameEN(id)) }
    if #assign > 0 then
        out[#out + 1] = "Assignments:"
        for _, a in ipairs(assign) do
            local tg = TargetsText(a)
            out[#out + 1] = Clean(a.text) .. (tg ~= "" and (" (" .. tg .. ")") or "")
        end
    end
    local lastPhase, count = nil, 0
    for _, e in ipairs(kept) do
        if count >= MAX_LINES then
            out[#out + 1] = "... more in RaidTools"
            break
        end
        if e.phase ~= lastPhase then
            if e.phase == 1 then
                out[#out + 1] = "-- PHASE 1 --"
            else
                local est = phases[e.phase]
                local label = ns.PhaseLabel(e.phase)
                if e.phase ~= math.floor(e.phase) then label = label .. " " .. tostring(e.phase) end
                out[#out + 1] = ("-- %s%s --"):format(label, est and (" (around " .. FormatTime(est) .. ")") or "")
            end
            lastPhase = e.phase
        end
        local timeTag = e.phase == 1 and ("{time:%s}"):format(FormatTime(e.time))
            or ("{time:%s,p%s}"):format(FormatTime(e.time), tostring(e.phase))
        local tg = TargetsText(e)
        out[#out + 1] = timeTag .. " " .. Clean(e.text) .. (tg ~= "" and (" (" .. tg .. ")") or "")
        count = count + 1
    end
    return table.concat(out, "\n")
end

-- Envoie la note par le canal de note de MRT. MRT n'accepte en raid qu'une note du chef ou d'un assistant.
function ns.SendMRTNote(id, verbose)
    id = tonumber(id) or 0
    local function Fail(msg)
        if verbose then ns.Print(msg) end
        return false
    end
    if ns.Locked() then return Fail("Envoi impossible pendant une rencontre.") end
    local channel = ns.GroupChannel()
    if not channel then return Fail("Tu n'es pas en groupe.") end
    if IsInRaid() and not ns.IsLeaderOrAssist() then
        return Fail("MRT n'accepte une note que du chef de raid ou d'un assistant.")
    end
    local text = ns.BuildMRTNote(id)
    if not text then
        return Fail("Rien à mettre dans la note MRT : il faut des lignes !rw, rc ou ciblées sur des joueurs.")
    end
    local index = ("%d%04d"):format(time(), math.random(0, 9999))
    for _, part in ipairs(ns.SplitText(text, 200)) do
        ns.RawSend("EXRTADD", "multiline\t" .. index .. "\t" .. part, channel)
    end
    local name = Clean(ns.EncounterNameEN(id))
    ns.RawSend("EXRTADD", ("multiline_add\t%s\t%s\t%s"):format(index, id ~= 0 and tostring(id) or "-", name), channel)
    return true
end
