-- RaidTools : annonces en alerte raid pendant les rencontres, pour les joueurs SANS l'addon.
--
-- Pendant un boss, Midnight bloque tout message envoyé automatiquement par un addon.
-- Seule une action du joueur (clic ou touche) peut envoyer « /rw ». On prépare donc, hors combat,
-- un bouton sécurisé qui contient la liste ordonnée des rappels marqués !rw du boss :
-- chaque appui sur sa touche envoie le message suivant en alerte raid.
-- Quand un rappel !rw arrive, l'addon du chef affiche « Annonce : … (touche) » pour le guider.
-- Le bouton de phase (barre de calls) fonctionne pareil : « /rw >> PHASE 2 << » puis recalage des rappels.

local _, ns = ...

local announceButton
local prepared = { id = nil, list = {}, index = 1 }

function ns.KeyText(buttonName)
    local key = GetBindingKey("CLICK " .. buttonName .. ":LeftButton")
    return key and GetBindingText(key, "KEY_") or nil
end
local KeyText = ns.KeyText

-- Messages !rw du boss, triés par moment prévu (début de phase estimé + temps).
local function BuildList(encounterID)
    local entries, phases = ns.ParseNote(ns.db.notes[encounterID])
    local list = {}
    for _, e in ipairs(entries) do
        local start = (e.phase == 1) and 0 or phases[e.phase]
        if e.rw and start then
            local msg = e.text
            if e.targets then msg = msg .. " (" .. table.concat(e.targets, ", ") .. ")" end
            list[#list + 1] = { at = start + e.time, msg = msg }
        end
    end
    table.sort(list, function(a, b) return a.at < b.at end)
    return list
end

-- Charge les annonces d'un boss dans le bouton sécurisé (uniquement hors combat).
function ns.PrepareAnnounces(encounterID)
    if not announceButton or InCombatLockdown() then return false end
    encounterID = tonumber(encounterID) or 0
    local list = BuildList(encounterID)
    for i = 1, math.max(#list, prepared.count or 0) do
        announceButton:SetAttribute("rt-msg" .. i, list[i] and list[i].msg or nil)
    end
    announceButton:SetAttribute("rt-count", #list)
    announceButton:SetAttribute("rt-index", 1)
    announceButton:SetAttribute("macrotext", nil)
    prepared.id, prepared.list, prepared.index, prepared.count = encounterID, list, 1, #list
    ns.UpdateAnnounceButton()
    if ns.PrepareCalls then ns.PrepareCalls(encounterID) end
    return true
end

function ns.UpdateAnnounceButton()
    if not announceButton then return end
    local nextMsg = prepared.list[prepared.index]
    local label
    local key = KeyText("RaidToolsAnnounceButton")
    if #prepared.list == 0 then
        label = "Annonce !rw : aucune"
    elseif nextMsg then
        label = ("Annonce %d/%d : %s"):format(prepared.index, #prepared.list, nextMsg.msg)
    else
        label = "Annonces terminées"
    end
    announceButton.text:SetText(key and (label .. "  |cff808080" .. key .. "|r") or label)
end

-- Appelé par Reminders quand un rappel !rw tombe et que le chef ne peut pas l'envoyer lui-même.
function ns.PromptAnnounce(msg)
    local key = KeyText("RaidToolsAnnounceButton")
    ns.ShowAlert(("|cff3bc4b5Annonce :|r %s\n|cffaaaaaa%s|r"):format(msg,
        key and ("appuie sur " .. key) or "clique sur le bouton Annonce"), { color = { 1, 1, 1 }, sound = true })
end

-- Le chef annonce-t-il les rappels !rw de cette rencontre ?
function ns.IsPreparedFor(encounterID)
    return prepared.id == tonumber(encounterID) and #prepared.list > 0
end

----------------------------------------------------------------------
-- Bouton sécurisé (créé par la barre de calls)
----------------------------------------------------------------------

-- Le bouton n'agit que sur l'appui ou le relâchement, selon le réglage du jeu, pour ne pas avancer deux fois.
function ns.RegisterSecureClicks(button)
    button:RegisterForClicks(GetCVarBool("ActionButtonUseKeyDown") and "AnyDown" or "AnyUp")
end

function ns.SetupAnnounceButton(button)
    announceButton = button
    announceButton:SetAttribute("type", "macro")
    ns.RegisterSecureClicks(announceButton)
    -- Code exécuté par le jeu avant l'action, même en combat : on prend le message suivant.
    SecureHandlerWrapScript(announceButton, "OnClick", ns.secureHeader, [[
        local i = self:GetAttribute("rt-index") or 1
        local n = self:GetAttribute("rt-count") or 0
        if i > n then
            self:SetAttribute("macrotext", nil)
            return
        end
        self:SetAttribute("macrotext", "/rw " .. (self:GetAttribute("rt-msg" .. i) or ""))
        self:SetAttribute("rt-index", i + 1)
    ]])
    announceButton:SetScript("PostClick", function()
        if prepared.list[prepared.index] then
            ns.lastOwnWarning = GetTime()
            prepared.index = prepared.index + 1
        end
        ns.UpdateAnnounceButton()
    end)
    ns.UpdateAnnounceButton()
end
