-- RaidTools : affichage des alertes (texte central) et des barres de timer.

local _, ns = ...

local FLAT = "Interface\\Buttons\\WHITE8x8"
local alert, barHolder
local bars, barPool = {}, {}

----------------------------------------------------------------------
-- Synthèse vocale
----------------------------------------------------------------------

local function VoiceID()
    if C_TTSSettings and C_TTSSettings.GetVoiceOptionID and Enum.TtsVoiceType then
        local ok, id = pcall(C_TTSSettings.GetVoiceOptionID, Enum.TtsVoiceType.Standard)
        if ok and id then return id end
    end
    local voices = C_VoiceChat and C_VoiceChat.GetTtsVoices and C_VoiceChat.GetTtsVoices()
    return voices and voices[1] and voices[1].voiceID or 0
end

-- Tes propres sons : Interface\AddOns\RaidTools\Sounds\soak.ogg est joué à la place de la voix
-- pour un call ou un rappel « SOAK » (nom en minuscules, espaces remplacés par _ , sans accents ni ponctuation).
-- Les sons LibSharedMedia (si un autre addon la fournit) sont aussi utilisés quand le nom correspond.
local SOUND_DIR = "Interface\\AddOns\\RaidTools\\Sounds\\"
local ACCENTS = { ["à"] = "a", ["â"] = "a", ["ç"] = "c", ["é"] = "e", ["è"] = "e", ["ê"] = "e", ["ë"] = "e",
    ["î"] = "i", ["ï"] = "i", ["ô"] = "o", ["ù"] = "u", ["û"] = "u", ["ü"] = "u" }

local function SoundKey(text)
    local key = strlower((tostring(text):gsub("{%w+}", "")))
    for from, to in pairs(ACCENTS) do key = key:gsub(from, to) end
    key = key:gsub("[^%w%s_]", ""):gsub("%s+", "_"):gsub("^_+", ""):gsub("_+$", "")
    return key
end

local function TryKey(text)
    local key = SoundKey(text)
    if key == "" then return false end
    local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
    local path = LSM and LSM:Fetch("sound", text, true)
    if path and PlaySoundFile(path, "Master") then return true end
    for _, ext in ipairs({ ".ogg", ".mp3" }) do
        if PlaySoundFile(SOUND_DIR .. key .. ext, "Master") then return true end
    end
    return false
end

-- « Soak : Toxic Droplets » ou « SOAK - Toxic Droplets » essaie soak_toxic_droplets puis soak.
local function PlayCustomSound(text)
    text = tostring(text)
    if TryKey(text) then return true end
    local head = text:match("^(.-)%s*:") or text:match("^(.-)%s+%-%s")
    return head and head ~= "" and TryKey(head) or false
end

function ns.Speak(text)
    -- Voix coupée : ni synthèse vocale, ni sons perso, ni décompte.
    if not text or not ns.db.alert.tts then return end
    if ns.db.alert.customSounds ~= false and PlayCustomSound(text) then return end
    if not (ns.db.alert.tts and C_VoiceChat and C_VoiceChat.SpeakText) then return end
    local rate = (C_TTSSettings and C_TTSSettings.GetSpeechRate and C_TTSSettings.GetSpeechRate()) or ns.db.alert.ttsRate
    -- Signature Midnight : voix, texte, vitesse, volume, superposition.
    pcall(C_VoiceChat.SpeakText, VoiceID(), tostring(text), rate, ns.db.alert.ttsVolume, true)
end

-- Décompte vocal « 3, 2, 1 » qui se termine à l'instant 'inSeconds'. Utilise 3.ogg, 2.ogg... si présents.
-- Renvoie les timers pour pouvoir les annuler.
function ns.SpeakCountdown(inSeconds, from)
    local timers = {}
    for i = from, 1, -1 do
        local delay = inSeconds - i
        if delay >= 0 then
            timers[#timers + 1] = C_Timer.NewTimer(delay, function() ns.Speak(tostring(i)) end)
        end
    end
    return timers
end

----------------------------------------------------------------------
-- Alerte centrale
----------------------------------------------------------------------

-- {rt1}..{rt8} et {star}, {skull}… deviennent les icônes de marqueur, comme dans le chat.
local MARKERS = { star = 1, circle = 2, diamond = 3, triangle = 4, moon = 5, square = 6, cross = 7, x = 7, skull = 8,
    etoile = 1, cercle = 2, losange = 3, lune = 5, carre = 6, croix = 7, crane = 8 }
function ns.FormatIcons(text)
    return (tostring(text):gsub("{(%w+)}", function(token)
        local id = MARKERS[strlower(token)] or tonumber(strlower(token):match("^rt(%d)$"))
        if id then return "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_" .. id .. ":0|t" end
    end))
end

-- opts : color = {r,g,b}, sound = bool, tts = texte à lire (ou true pour lire le texte)
function ns.ShowAlert(text, opts)
    if not alert or ns.db.alert.show == false then return end
    if opts and opts.tts == true then opts.tts = text end
    if opts and type(opts.tts) == "string" then opts.tts = opts.tts:gsub("{%w+}", "") end
    text = ns.FormatIcons(text)
    opts = opts or {}
    local c = opts.color or { 1, 0.82, 0.2 }
    -- Deux alertes quasi simultanées : on les empile au lieu d'écraser la première.
    local now = GetTime()
    if alert.lastShow and now - alert.lastShow < 0.75 and alert:IsShown() and alert.lastText then
        local _, lines = alert.lastText:gsub("\n", "")
        if lines < 2 then text = alert.lastText .. "\n" .. text end
    end
    alert.lastShow, alert.lastText = now, text
    alert.text:SetText(text)
    alert.text:SetTextColor(c[1], c[2], c[3])
    alert.anim:Stop()
    alert:SetAlpha(1)
    alert:Show()
    alert.anim:Play()
    if opts.sound and ns.db.alert.sound then
        PlaySound(SOUNDKIT.RAID_WARNING, "Master")
    end
    if opts.tts then
        ns.Speak(opts.tts == true and text or opts.tts)
    end
end

-- Alerte raid reçue du chat. Pendant une rencontre le texte peut être une valeur secrète :
-- aucune opération de chaîne, on le passe directement à l'affichage et à la voix.
function ns.ShowRaidWarning(text)
    if not alert or ns.db.alert.show == false then return end
    alert.anim:Stop()
    alert.lastText = nil
    alert.text:SetText(text)
    alert.text:SetTextColor(1, 0.82, 0.2)
    alert:SetAlpha(1)
    alert:Show()
    alert.anim:Play()
    if ns.db.alert.sound then PlaySound(SOUNDKIT.RAID_WARNING, "Master") end
    if ns.db.alert.tts and C_VoiceChat and C_VoiceChat.SpeakText then
        local rate = (C_TTSSettings and C_TTSSettings.GetSpeechRate and C_TTSSettings.GetSpeechRate()) or 0
        pcall(C_VoiceChat.SpeakText, VoiceID(), text, rate, ns.db.alert.ttsVolume, true)
    end
end

----------------------------------------------------------------------
-- Barres de timer
----------------------------------------------------------------------

local function FormatTime(s)
    if s >= 60 then return ("%d:%02d"):format(s / 60, s % 60) end
    if s >= 10 then return ("%d"):format(s) end
    return ("%.1f"):format(s)
end

local function LayoutBars()
    local list = {}
    for _, bar in pairs(bars) do list[#list + 1] = bar end
    table.sort(list, function(a, b) return a.expires < b.expires end)
    for i, bar in ipairs(list) do
        bar:ClearAllPoints()
        bar:SetPoint("TOP", barHolder, "TOP", 0, -(i - 1) * 26)
    end
end

local function AcquireBar()
    local bar = table.remove(barPool)
    if bar then return bar end
    bar = CreateFrame("StatusBar", nil, barHolder, "BackdropTemplate")
    bar:SetSize(280, 22)
    bar:SetStatusBarTexture(FLAT)
    bar:SetBackdrop({ bgFile = FLAT, edgeFile = FLAT, edgeSize = 1 })
    bar:SetBackdropColor(0.06, 0.06, 0.08, 0.85)
    bar:SetBackdropBorderColor(0, 0, 0, 1)
    bar.label = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    bar.label:SetPoint("LEFT", 6, 0)
    bar.label:SetPoint("RIGHT", -44, 0)
    bar.label:SetJustifyH("LEFT")
    bar.time = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    bar.time:SetPoint("RIGHT", -6, 0)
    return bar
end

-- total : durée pleine de la barre (par défaut = duration, le temps restant).
function ns.StartBar(id, label, duration, color, total)
    if not barHolder or (ns.db.showBars == false and not id:find("^demo")) then return end
    ns.StopBar(id)
    local bar = AcquireBar()
    local c = color or ns.accent
    bar:SetStatusBarColor(c[1], c[2], c[3], 0.9)
    bar:SetMinMaxValues(0, total or duration)
    bar.label:SetText(label)
    bar.duration = duration
    bar.expires = GetTime() + duration
    bar.id = id
    bar.shownValue = nil
    bars[id] = bar
    bar:Show()
    barHolder:Show()
    LayoutBars()
end

function ns.StopBar(id)
    local bar = bars[id]
    if not bar then return end
    bars[id] = nil
    bar:Hide()
    barPool[#barPool + 1] = bar
    -- Plus aucune barre : le cadre est masqué, sa boucle d'affichage s'arrête.
    if not next(bars) then barHolder:Hide() end
    LayoutBars()
end

function ns.StopAllBars(filter)
    for id in pairs(bars) do
        if not filter or tostring(id):find(filter, 1, true) then ns.StopBar(id) end
    end
end

----------------------------------------------------------------------
-- Création, déplacement
----------------------------------------------------------------------

function ns.SetAlertsLocked(locked)
    alert.locked = locked
    alert:EnableMouse(not locked)
    if locked then
        ns.StopAllBars("demo")
        if ns.SetTrackerPreview then ns.SetTrackerPreview(false) end
        alert.bg:Hide()
        alert:Hide()
        if ns.SetEditMode then ns.SetEditMode(false) end
        local p, _, _, x, y = alert:GetPoint()
        ns.db.alert.point, ns.db.alert.x, ns.db.alert.y = p, x, y
        ns.Print("alertes verrouillées.")
    else
        -- Aperçu : une alerte et des barres d'exemple, le tout déplaçable à la souris.
        alert.anim:Stop()
        alert.text:SetText(ns.FormatIcons("SOAK LEFT {rt1}") .. "\n|cffffffffAperçu RaidTools : glisse-moi|r")
        alert.text:SetTextColor(1, 0.82, 0.2)
        alert:SetAlpha(1)
        alert.bg:Show()
        alert:Show()
        ns.StartBar("demo1", "Tankbuster : Example", 4, nil, 5)
        ns.StartBar("demo2", "AoE : Example", 12, { 0.85, 0.35, 0.3 }, 15)
        ns.StartBar("demo3", "Break", 240, { 0.35, 0.6, 1 }, 300)
        ns.Speak("Soak left")
        if ns.SetTrackerPreview then ns.SetTrackerPreview(true) end
        if ns.SetEditMode then ns.SetEditMode(true) end
        ns.Print("mode édition : glisse les fenêtres, la roue règle taille, opacité et affichage, la poignée agrandit. |cff3bc4b5/rt lock|r pour finir.")
    end
end

function ns.InitAlerts()
    local db = ns.db.alert
    alert = CreateFrame("Frame", "RaidToolsAlertFrame", UIParent)
    alert:SetSize(700, 60)
    alert:SetPoint(db.point, UIParent, db.point, db.x, db.y)
    alert:SetScale(db.scale)
    alert:SetFrameStrata("HIGH")
    alert:SetMovable(true)
    alert:SetClampedToScreen(true)
    alert:RegisterForDrag("LeftButton")
    alert:SetScript("OnDragStart", alert.StartMoving)
    alert:SetScript("OnDragStop", alert.StopMovingOrSizing)
    alert:EnableMouse(false)
    alert.locked = true
    alert:Hide()

    alert.bg = alert:CreateTexture(nil, "BACKGROUND")
    alert.bg:SetAllPoints()
    alert.bg:SetColorTexture(ns.accent[1], ns.accent[2], ns.accent[3], 0.25)
    alert.bg:Hide()

    alert.text = alert:CreateFontString(nil, "OVERLAY")
    alert.text:SetFont(STANDARD_TEXT_FONT, 34, "OUTLINE")
    alert.text:SetShadowOffset(2, -2)
    alert.text:SetPoint("CENTER")

    local ag = alert:CreateAnimationGroup()
    local pop = ag:CreateAnimation("Scale")
    pop:SetScaleFrom(1.25, 1.25)
    pop:SetScaleTo(1, 1)
    pop:SetDuration(0.15)
    pop:SetOrder(1)
    local fade = ag:CreateAnimation("Alpha")
    fade:SetFromAlpha(1)
    fade:SetToAlpha(0)
    fade:SetStartDelay(3)
    fade:SetDuration(0.6)
    fade:SetOrder(2)
    ag:SetScript("OnFinished", function()
        if alert.locked then alert:Hide() end
    end)
    alert.anim = ag

    -- Parent UIParent : les barres restent visibles même quand le texte d'alerte est masqué.
    barHolder = CreateFrame("Frame", "RaidToolsBarHolder", UIParent)
    barHolder:SetSize(280, 1)
    barHolder:SetPoint("TOP", alert, "BOTTOM", 0, -8)
    barHolder:SetScale(db.scale)

    barHolder:Hide()

    -- 25 images par seconde pour la barre ; le texte n'est réécrit que quand le chiffre affiché change.
    local acc = 0
    barHolder:SetScript("OnUpdate", function(_, dt)
        acc = acc + dt
        if acc < 0.04 then return end
        acc = 0
        local now = GetTime()
        for id, bar in pairs(bars) do
            local left = bar.expires - now
            if left <= 0 then
                ns.StopBar(id)
            else
                bar:SetValue(left)
                local shown = left >= 10 and math.floor(left) or math.floor(left * 10)
                if shown ~= bar.shownValue then
                    bar.shownValue = shown
                    bar.time:SetText(FormatTime(left))
                end
            end
        end
    end)
end
