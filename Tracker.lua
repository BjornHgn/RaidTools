-- RaidTools : panneau de suivi pendant le boss.
--   PHASE 2                        1:23
--   ▸ Soak : Toxic Droplets        8 s
--     AoE : Contaminate           14 s
--     Tankbuster : Slam           21 s
--   Phase 3 dans ~45 s
-- Couleur par type de mécanique, pour lire d'un coup d'œil ce qui arrive.
-- En haut à droite : les charges de rez de combat du raid, avec la recharge en cours.

local _, ns = ...

local FLAT = "Interface\\Buttons\\WHITE8x8"
local frame
local rows = {}
local preview = false

local KIND_COLORS = {
    { "^tankbuster", { 1, 0.35, 0.35 } },
    { "^aoe", { 1, 0.6, 0.25 } },
    { "^soak", { 0.75, 0.5, 1 } },
    { "^adds", { 0.4, 1, 0.5 } },
    { "^phase", ns.accent },
    { "^spread", { 0.4, 0.75, 1 } },
    { "^frontal", { 1, 0.85, 0.3 } },
    { "^knock", { 1, 0.85, 0.3 } },
    { "^debuff", { 0.85, 0.55, 0.85 } },
}

local function ColorFor(text)
    local lower = strlower(text)
    for _, kc in ipairs(KIND_COLORS) do
        if lower:find(kc[1]) then return kc[2] end
    end
    return { 1, 1, 1 }
end

local function Clock(s)
    s = math.max(0, math.floor(s))
    return ("%d:%02d"):format(math.floor(s / 60), s % 60)
end

-- Rez de combat : valeurs parfois secrètes en combat, donc seulement passées à l'affichage.
local function RenderBattleRes(br)
    if not br then
        frame.brez:Hide()
        return
    end
    frame.brez:Show()
    pcall(frame.brez.count.SetText, frame.brez.count, br.currentCharges)
    pcall(frame.brez.cd.SetCooldown, frame.brez.cd, br.cooldownStartTime, br.cooldownDuration)
end

local function Render(info)
    frame.phase:SetText(info.phase and ns.PhaseLabel(info.phase) or "BOSS")
    frame.clock:SetText(Clock(info.inPhase))
    for i = 1, 3 do
        local row, u = rows[i], (i <= info.count) and info.upcoming[i] or nil
        if u then
            local c = ColorFor(u.text)
            row.bar:SetVertexColor(c[1], c[2], c[3], 1)
            row.label:SetText(ns.FormatIcons(u.text))
            row.label:SetTextColor(i == 1 and 1 or 0.85, i == 1 and 1 or 0.85, i == 1 and 1 or 0.85)
            row.time:SetText(u.inSec < 10 and ("%.1f s"):format(u.inSec) or ("%d s"):format(u.inSec))
            row.time:SetTextColor(u.inSec < 5 and 1 or 0.8, u.inSec < 5 and 0.35 or 0.8, u.inSec < 5 and 0.35 or 0.8)
            row:Show()
        else
            row:Hide()
        end
    end
    if info.nextPhase and info.nextIn then
        frame.footer:SetText(("%s dans ~%s"):format(ns.PhaseLabel(info.nextPhase), Clock(info.nextIn)))
    elseif info.bossOnly then
        frame.footer:SetText("Pas de rappel pour ce boss")
    else
        frame.footer:SetText(info.count == 0 and "Plus de rappel pour toi" or "")
    end
    RenderBattleRes(info.brez)
end

local PREVIEW_INFO = {
    phase = 2, inPhase = 83,
    upcoming = {
        { text = "Soak : Toxic Droplets", inSec = 4.2 },
        { text = "AoE : Contaminate", inSec = 14 },
        { text = "Tankbuster : Empowering Slam", inSec = 21 },
    },
    count = 3,
    nextPhase = 3, nextIn = 45,
    brez = { currentCharges = 1, cooldownStartTime = 0, cooldownDuration = 0 },
}

-- 5 rafraîchissements par seconde suffisent, et rien ne tourne quand le panneau est masqué.
local bossOnlyInfo = { upcoming = {}, count = 0, bossOnly = true }
local elapsedSince = 0
local function OnUpdate(_, dt)
    elapsedSince = elapsedSince + dt
    if elapsedSince < 0.2 then return end
    elapsedSince = 0
    if preview then
        Render(PREVIEW_INFO)
        return
    end
    local info = ns.db.showTracker and ns.GetRunInfo(3)
    if not info and ns.db.showTracker and ns.encounterStart then
        -- Boss sans rappel : le panneau garde le chrono du combat et les rez.
        info = bossOnlyInfo
        info.inPhase = GetTime() - ns.encounterStart
    end
    if not info then
        frame:Hide()
        return
    end
    info.brez = ns.GetBattleRes()
    Render(info)
end

function ns.InitTracker()
    frame = CreateFrame("Frame", "RaidToolsTracker", UIParent, "BackdropTemplate")
    frame:SetSize(280, 118)
    frame:SetPoint("BOTTOM", RaidToolsAlertFrame, "TOP", 0, 8)
    frame:SetScale(ns.db.alert.scale or 1)
    frame:SetBackdrop({ bgFile = FLAT, edgeFile = FLAT, edgeSize = 1 })
    frame:SetBackdropColor(0.05, 0.05, 0.07, 0.8)
    frame:SetBackdropBorderColor(0, 0, 0, 1)
    frame:Hide()

    local accent = frame:CreateTexture(nil, "ARTWORK")
    accent:SetColorTexture(ns.accent[1], ns.accent[2], ns.accent[3], 1)
    accent:SetPoint("TOPLEFT", 1, -1)
    accent:SetPoint("TOPRIGHT", -1, -1)
    accent:SetHeight(2)

    frame.phase = frame:CreateFontString(nil, "OVERLAY")
    frame.phase:SetFont(STANDARD_TEXT_FONT, 16, "OUTLINE")
    frame.phase:SetTextColor(ns.accent[1], ns.accent[2], ns.accent[3])
    frame.phase:SetPoint("TOPLEFT", 10, -10)
    frame.clock = frame:CreateFontString(nil, "OVERLAY")
    frame.clock:SetFont(STANDARD_TEXT_FONT, 16, "OUTLINE")
    frame.clock:SetPoint("TOPRIGHT", -10, -10)

    -- Rez de combat : icône de Renaissance, nombre de charges, recharge en balayage.
    local brez = CreateFrame("Frame", nil, frame)
    brez:SetSize(18, 18)
    brez.count = brez:CreateFontString(nil, "OVERLAY")
    brez.count:SetFont(STANDARD_TEXT_FONT, 14, "OUTLINE")
    brez.count:SetPoint("RIGHT", frame.clock, "LEFT", -12, 0)
    brez:SetPoint("RIGHT", brez.count, "LEFT", -4, 0)
    brez.icon = brez:CreateTexture(nil, "ARTWORK")
    brez.icon:SetAllPoints()
    brez.icon:SetTexture((C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(20484)) or 136080)
    brez.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    brez.cd = CreateFrame("Cooldown", nil, brez, "CooldownFrameTemplate")
    brez.cd:SetAllPoints()
    if brez.cd.SetHideCountdownNumbers then brez.cd:SetHideCountdownNumbers(true) end
    brez:Hide()
    frame.brez = brez

    for i = 1, 3 do
        local row = CreateFrame("Frame", nil, frame)
        row:SetSize(260, 18)
        row:SetPoint("TOPLEFT", 10, -34 - (i - 1) * 20)
        row.bar = row:CreateTexture(nil, "ARTWORK")
        row.bar:SetTexture(FLAT)
        row.bar:SetSize(3, 14)
        row.bar:SetPoint("LEFT")
        row.label = row:CreateFontString(nil, "OVERLAY", i == 1 and "GameFontHighlight" or "GameFontHighlightSmall")
        row.label:SetPoint("LEFT", 9, 0)
        row.label:SetPoint("RIGHT", -48, 0)
        row.label:SetJustifyH("LEFT")
        row.label:SetWordWrap(false)
        row.time = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.time:SetPoint("RIGHT")
        rows[i] = row
    end

    frame.footer = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    frame.footer:SetPoint("BOTTOMLEFT", 10, 8)

    frame:SetScript("OnUpdate", OnUpdate)
end

-- Appelé au début des rappels (rencontre ou test).
function ns.ShowTracker()
    if frame and ns.db.showTracker then frame:Show() end
end

function ns.SetTrackerPreview(on)
    preview = on
    if not frame then return end
    if on then frame:Show() else frame:Hide() end
end
