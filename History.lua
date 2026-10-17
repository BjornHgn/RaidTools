-- RaidTools : résumé des pulls (onglet Pulls).
-- Le jeu ne laisse plus les addons lire le journal de combat : on garde ce que l'addon voit lui-même
-- pendant le boss (durée, kill ou wipe, morts et rez dans l'ordre, phases, calls).
-- Rien ne part au raid tout seul : seul le bouton « Poster au raid » envoie le résumé, en anglais.

local _, ns = ...

local MAX_PULLS, MAX_EVENTS = 30, 200
local cur, timer
local dead = {}

local DIFF = { [14] = "N", [15] = "H", [16] = "M", [17] = "LFR", [8] = "M+", [23] = "M" }
local DIFF_EN = { [14] = "Normal", [15] = "Heroic", [16] = "Mythic", [17] = "LFR", [8] = "Mythic+", [23] = "Mythic" }

-- Valeur lisible par l'addon (les valeurs secrètes de Midnight sont ignorées).
local function Plain(v)
    if v == nil or (issecretvalue and issecretvalue(v)) then return nil end
    return v
end

function ns.Clock(s)
    s = math.max(0, math.floor((s or 0) + 0.5))
    return ("%d:%02d"):format(math.floor(s / 60), s % 60)
end

local function Add(kind, text, class)
    if not cur or #cur.events >= MAX_EVENTS then return end
    local t = math.floor((GetTime() - cur.t0) * 10 + 0.5) / 10
    local last = cur.events[#cur.events]
    -- Une même phase signalée deux fois de suite (touche Phase puis recalage) ne compte qu'une fois.
    if kind == "phase" and last and last[2] == "phase" and last[3] == text and t - last[1] < 2 then return end
    cur.events[#cur.events + 1] = { t, kind, text, class }
end

local function EachUnit(fn)
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do fn("raid" .. i) end
    else
        fn("player")
        for i = 1, GetNumSubgroupMembers() do fn("party" .. i) end
    end
end

local function Scan(first)
    if not cur then return end
    EachUnit(function(unit)
        local name = Plain(UnitName(unit))
        local isDead = Plain(UnitIsDeadOrGhost(unit))
        if not name or isDead == nil then return end
        if first then
            dead[name] = isDead
        elseif isDead and not dead[name] then
            dead[name] = true
            cur.deaths = cur.deaths + 1
            Add("death", name, Plain(select(2, UnitClass(unit))))
        elseif not isDead and dead[name] then
            dead[name] = false
            Add("rez", name, Plain(select(2, UnitClass(unit))))
        end
    end)
end

local function Tick()
    Scan()
    if cur then timer = C_Timer.NewTimer(0.5, Tick) end
end

local function Start(id, name, diff, size)
    if timer then timer:Cancel() end
    dead = {}
    cur = { id = id, name = name, diff = diff, size = size, date = time(), t0 = GetTime(), events = {}, deaths = 0 }
    Scan(true)
    timer = C_Timer.NewTimer(0.5, Tick)
end

local function Finish(success)
    if not cur then return end
    if timer then timer:Cancel(); timer = nil end
    Scan()
    local p = cur
    cur = nil
    p.dur = math.floor((GetTime() - p.t0) * 10 + 0.5) / 10
    p.kill = success == 1 or success == true
    p.t0 = nil
    local list = ns.db.history
    table.insert(list, 1, p)
    while #list > MAX_PULLS do table.remove(list) end
    ns.historySelected = 1
    local first = ns.FirstDeath(p)
    ns.Print(("%s : %s en %s, %d mort%s%s. Détail : onglet Pulls."):format(
        p.kill and "|cff55ff55Kill|r" or "|cffff5555Wipe|r", p.name or "?", ns.Clock(p.dur), p.deaths,
        p.deaths > 1 and "s" or "", first and (" (1er : %s à %s)"):format(first[3], ns.Clock(first[1])) or ""))
    if ns.RefreshUI then ns.RefreshUI() end
end

function ns.FirstDeath(p)
    for _, e in ipairs(p.events) do
        if e[2] == "death" then return e end
    end
end

function ns.DiffShort(diff) return DIFF[diff] end

-- Résumé en anglais pour le chat raid (bouton « Poster au raid » seulement).
function ns.PostPull(p)
    if not p then return end
    local deaths = {}
    for _, e in ipairs(p.events) do
        if e[2] == "death" and #deaths < 5 then deaths[#deaths + 1] = ("%s %s"):format(e[3], ns.Clock(e[1])) end
    end
    local head = ("%s%s - %s %s - %d death%s"):format(p.name or "?",
        DIFF_EN[p.diff] and (" (" .. DIFF_EN[p.diff] .. ")") or "",
        p.kill and "Kill" or "Wipe", ns.Clock(p.dur), p.deaths, p.deaths == 1 and "" or "s")
    ns.Announce(head)
    if #deaths > 0 then ns.Announce("First deaths: " .. table.concat(deaths, ", ")) end
end

function ns.ClearHistory()
    wipe(ns.db.history)
    ns.historySelected = nil
    if ns.RefreshUI then ns.RefreshUI() end
end

local f = CreateFrame("Frame")
f:RegisterEvent("ENCOUNTER_START")
f:RegisterEvent("ENCOUNTER_END")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_LOGIN" then
        -- Calls et phases lancés par le chef pendant le pull.
        hooksecurefunc(ns, "Call", function(text)
            text = Plain(text)
            if text and text ~= "" then Add("call", text) end
        end)
        hooksecurefunc(ns, "SetPhaseIndex", function(k) Add("phase", ns.PlanPhaseLabel(k)) end)
        hooksecurefunc(ns, "SetPhase", function(phase) Add("phase", ns.PhaseLabel(phase)) end)
    elseif event == "ENCOUNTER_START" then
        local id, name, diff, size = ...
        Start(Plain(id), Plain(name), Plain(diff), Plain(size))
    elseif event == "ENCOUNTER_END" then
        local _, _, _, _, success = ...
        Finish(Plain(success))
    end
end)
