-- RaidTools : import des notes au format NSRT (celles partagées sur les sites de guides et par les guildes).
--
-- Format reconnu (une ligne par rappel, champs séparés par ;) :
--   EncounterID:3455;Name:Ma note;Difficulty:Mythic
--   time:42;tag:group1 group2;text:Soak gauche;ph:1
--   time:95;tag:everyone;spellid:1282516
--   assign:{rt1} Soak gauche;tag:group1
-- Chaque ligne est convertie dans la syntaxe RaidTools, puis reste modifiable dans l'éditeur.

local _, ns = ...

local CLASS_BY_ID = { "guerrier", "paladin", "chasseur", "voleur", "prêtre", "dk", "chaman", "mage",
    "démoniste", "moine", "druide", "dh", "évocateur" }

local function FormatTime(t)
    t = math.floor(t + 0.5)
    return ("%d:%02d"):format(math.floor(t / 60), t % 60)
end

local function StripColors(text)
    return (text:gsub("||", "|"):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
end

-- Convertit les tags NSRT en cibles RaidTools. Renvoie nil pour « tout le monde ».
local function ConvertTags(tag)
    if not tag then return nil end
    local out = {}
    for word in strlower(tag):gmatch("%S+") do
        local num = tonumber(word)
        local group = word:match("^group(%d)$")
        if word == "everyone" then
            return nil
        elseif word == "healer" then
            out[#out + 1] = "heal"
        elseif word == "damager" then
            out[#out + 1] = "dps"
        elseif group then
            out[#out + 1] = "g" .. group
        elseif num and num <= 13 then
            out[#out + 1] = CLASS_BY_ID[num] or word
        else
            out[#out + 1] = word -- pseudo, tank, melee, ranged, ID de spé
        end
    end
    return #out > 0 and table.concat(out, ",") or nil
end

local function SpellName(id)
    id = tonumber(id)
    return id and C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id) or (id and ("Sort " .. id))
end

function ns.IsNSRTNote(text)
    return text and (text:find("time:%d") ~= nil or text:find("EncounterID:%d") ~= nil)
end

-- Renvoie encounterID (ou nil), le texte converti et le nombre de rappels.
function ns.ConvertNSRTNote(text)
    local encID = tonumber(text:match("EncounterID:(%d+)"))
    local diffName = text:match("Difficulty:([^;\n]+)")
    local diff = (diffName and strlower(diffName):find("myth")) and 16 or 15
    local lines, assigns, count, phasesUsed = {}, {}, 0, {}

    for line in (text .. "\n"):gmatch("([^\n]*)\n") do
        local assign = line:match("assign:([^;]+)")
        local time = tonumber(line:match("time:(%d*%.?%d+)"))
        local tag = line:match("tag:([^;]+)")
        if assign then
            local targets = ConvertTags(tag)
            assigns[#assigns + 1] = "rc " .. strtrim(StripColors(assign)) .. (targets and (" @" .. targets) or "")
        elseif time then
            local label = line:match("text:([^;]+)")
            label = label and strtrim(StripColors(label)) or SpellName(line:match("spellid:(%d+)"))
            if label and label ~= "" then
                local phase = tonumber(line:match("ph:(%d*%.?%d+)")) or 1
                local targets = ConvertTags(tag)
                local prefix = phase ~= 1 and ("p" .. tostring(phase) .. " ") or ""
                lines[#lines + 1] = { phase = phase, time = time,
                    text = prefix .. FormatTime(time) .. " " .. label .. (targets and (" @" .. targets) or "") }
                phasesUsed[phase] = true
                count = count + 1
            end
        end
    end
    table.sort(lines, function(a, b)
        if a.phase ~= b.phase then return a.phase < b.phase end
        return a.time < b.time
    end)

    local out = { ("# Note NSRT importée (%d rappels). Ajoute !rw aux lignes que tout le raid doit voir."):format(count) }
    -- Débuts de phase : repris des presets RaidTools quand le boss est connu.
    local preset = encID and ns.Presets and ns.Presets[encID] and ns.Presets[encID][diff]
    local needPhases = false
    for p in pairs(phasesUsed) do if p ~= 1 then needPhases = true end end
    if needPhases then
        out[#out + 1] = "# Débuts de phase estimés. En combat : Phase suivante pour recaler."
        local found = false
        for _, ph in ipairs(preset and preset.phases or {}) do
            if phasesUsed[ph[1]] then
                out[#out + 1] = ("phase %s %s"):format(tostring(ph[1]), FormatTime(ph[2]))
                found = true
            end
        end
        local auto = found and ns.AutoPhaseLine and ns.AutoPhaseLine(encID)
        if auto then out[#out + 1] = auto end
        if not found then
            out[#out + 1] = "# Débuts de phase inconnus : ajoute les lignes « phase 2 m:ss » toi-même."
        end
    end
    for _, a in ipairs(assigns) do out[#out + 1] = a end
    for _, l in ipairs(lines) do out[#out + 1] = l.text end
    return encID, table.concat(out, "\n"), count + #assigns
end

----------------------------------------------------------------------
-- Notes MRT (Method Raid Tools), celles que les leads et les sites de guides partagent.
--   {time:1:30} Texte            -> 1:30 Texte
--   {time:0:30,p2} Texte         -> p2 0:30 Texte
--   {spell:12345}                -> nom du sort dans la langue du jeu
--   {H}...{/H}, {T}...{/T}, {D}...{/D}, {p:Nom1,Nom2}...{/p}, {g12}...{/g}, {c:Mage}...{/c} -> @cibles
-- Les lignes sans temps sont gardées en commentaire (#) pour ne rien perdre.
----------------------------------------------------------------------

local ROLE_BLOCK = { h = "heal", t = "tank", d = "dps" }
local ICON_WORDS = { tank = "Tank", healer = "Heal", dps = "DPS" }

function ns.IsMRTNote(text)
    return text and text:find("{time:%d") ~= nil
end

-- Renvoie le texte converti et le nombre de rappels. encID sert à reprendre les débuts de phase des presets.
function ns.ConvertMRTNote(text, encID)
    local out, timed, comments, count, phasesUsed = {}, {}, {}, 0, {}
    local stack = {} -- blocs ouverts : { kind = "role" | "names" | "groups" | "classes" | "phase" | "other", targets = {} }

    local function Pop(kinds)
        for i = #stack, 1, -1 do
            if kinds[stack[i].kind] then
                table.remove(stack, i)
                return
            end
        end
    end

    for raw in (text .. "\n"):gmatch("([^\n]*)\n") do
        local line = StripColors(raw):gsub("{spell:(%d+):?%d*}", function(id) return SpellName(id) or "" end)
        local timeTag
        local closers = {}
        line = line:gsub("{([^}]*)}", function(tag)
            local lower = strlower(tag)
            if lower:find("^time:") then
                timeTag = timeTag or tag:sub(6)
                return ""
            elseif lower:find("^/") then
                closers[#closers + 1] = lower:sub(2)
                return ""
            elseif ROLE_BLOCK[lower] then
                stack[#stack + 1] = { kind = "role", targets = { ROLE_BLOCK[lower] } }
                return ""
            elseif lower:find("^!") then
                stack[#stack + 1] = { kind = lower:find("^!p") and "names" or "other", targets = {} }
                return ""
            elseif lower:find("^p:") then
                local names = {}
                for n in tag:sub(3):gmatch("[^,%s]+") do names[#names + 1] = n end
                stack[#stack + 1] = { kind = "names", targets = names }
                return ""
            elseif lower:find("^c:") then
                local classes = {}
                for c in lower:sub(3):gmatch("[^,%s]+") do classes[#classes + 1] = c end
                stack[#stack + 1] = { kind = "classes", targets = classes }
                return ""
            elseif lower:find("^g%d+$") then
                local groups = {}
                for d in lower:sub(2):gmatch("%d") do groups[#groups + 1] = "g" .. d end
                stack[#stack + 1] = { kind = "groups", targets = groups }
                return ""
            elseif lower:find("^p[%d%.]+$") or lower:find("^pg%d") then
                stack[#stack + 1] = { kind = "phase", targets = {} }
                return ""
            elseif lower:find("^[ez]:") or lower:find("^race:") or lower:find("^classunique:") or lower == "0" then
                stack[#stack + 1] = { kind = "other", targets = {} }
                return ""
            elseif lower == "everyone" or lower == "self" or lower:find("^icon:") then
                return ""
            elseif ICON_WORDS[lower] then
                return ICON_WORDS[lower]
            elseif lower:find("^rt%d$") or lower:find("^%a+$") and #lower <= 8 and ns.FormatIcons("{" .. lower .. "}") ~= "{" .. lower .. "}" then
                return "{" .. tag .. "}" -- marqueurs de raid : gardés
            end
            return tag
        end)

        -- Cibles = tous les blocs ouverts (y compris sur cette ligne).
        local targets, seen = {}, {}
        for _, b in ipairs(stack) do
            for _, t in ipairs(b.targets) do
                if not seen[t] then seen[t] = true; targets[#targets + 1] = t end
            end
        end
        for _, c in ipairs(closers) do
            local k = c:sub(1, 1)
            if ROLE_BLOCK[k] then Pop({ role = true })
            elseif k == "p" then Pop({ names = true, phase = true })
            elseif k == "g" then Pop({ groups = true })
            elseif k == "c" then Pop({ classes = true })
            else Pop({ other = true }) end
        end

        line = strtrim((line:gsub("%s+", " ")))
        local tg = #targets > 0 and (" @" .. table.concat(targets, ",")) or ""
        local converted = false
        if timeTag and line ~= "" then
            local ts, opts = timeTag:match("^([%d:%.]+)(.*)$")
            local secs
            if ts then
                local m, sec = ts:match("^(%d+):(%d+)")
                secs = m and (tonumber(m) * 60 + tonumber(sec)) or tonumber(ts)
            end
            local phase, usable = 1, secs ~= nil
            for opt in (opts or ""):gmatch("[^,]+") do
                opt = strlower(strtrim(opt))
                local p = opt:match("^p([%d%.]+)$")
                if p then
                    phase = tonumber(p) or 1
                elseif opt:find("^s[ca][csr]") or opt == "e" or opt:find("^pg") then
                    usable = false -- départ sur un événement de combat : pas de temps fixe
                end
            end
            if usable then
                local prefix = phase ~= 1 and ("p" .. tostring(phase) .. " ") or ""
                timed[#timed + 1] = { phase = phase, time = secs, text = prefix .. FormatTime(secs) .. " " .. line .. tg }
                phasesUsed[phase] = true
                count = count + 1
                converted = true
            end
        end
        if not converted and line ~= "" then
            comments[#comments + 1] = "# " .. line .. tg
        end
    end

    table.sort(timed, function(a, b)
        if a.phase ~= b.phase then return a.phase < b.phase end
        return a.time < b.time
    end)
    out[1] = ("# Note MRT importée (%d rappels). Ajoute !rw aux lignes que tout le raid doit voir."):format(count)
    local needPhases = false
    for p in pairs(phasesUsed) do if p ~= 1 then needPhases = true end end
    if needPhases then
        local preset = encID and ns.Presets and ns.Presets[encID] and ns.Presets[encID][15]
        out[#out + 1] = "# Débuts de phase estimés. En combat : Phase suivante pour recaler."
        local found = false
        for _, ph in ipairs(preset and preset.phases or {}) do
            if phasesUsed[ph[1]] then
                out[#out + 1] = ("phase %s %s"):format(tostring(ph[1]), FormatTime(ph[2]))
                found = true
            end
        end
        local auto = found and ns.AutoPhaseLine and ns.AutoPhaseLine(encID)
        if auto then out[#out + 1] = auto end
        if not found then
            out[#out + 1] = "# Débuts de phase inconnus : ajoute les lignes « phase 2 m:ss » toi-même."
        end
    end
    for _, l in ipairs(timed) do out[#out + 1] = l.text end
    if #comments > 0 then
        out[#out + 1] = ""
        out[#out + 1] = "# Lignes sans temps de la note MRT :"
        for _, c in ipairs(comments) do out[#out + 1] = c end
    end
    return table.concat(out, "\n"), count
end
