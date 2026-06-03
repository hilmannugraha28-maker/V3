-- ================================================================
--  Fish It! Plaza Booth Sniper v8.0
--  Sumber data: Replion "SaleListings" + "RAP" (bukan scan GUI)
--  Mencakup SEMUA seller: booth fisik + player tanpa booth
--  Auto server hop + Discord webhook
-- ================================================================

local Players            = game:GetService("Players")
local TeleportService    = game:GetService("TeleportService")
local HttpService        = game:GetService("HttpService")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")

local lp      = Players.LocalPlayer
local placeId = game.PlaceId
local jobId   = game.JobId

-- ────────────────────────────────
--  KONFIGURASI
-- ────────────────────────────────
local WEBHOOK      = "https://discord.com/api/webhooks/1510643221406027926/m47QLSX-EZgXLLJAfc_GcTMY8gzYouN8mTu0hnswem3bztNIcHrp7AEuszIyWmIwZwRv"
local WEBHOOK_INFO = "https://discord.com/api/webhooks/1510643283032801290/anFd_d8WkeCWZjkmgyDN0dxU5SiJ3z-OiyugpHxEFv9h1T2ldClV4a8jez_ehDQ8h7sz"

local SCAN_WAIT  = 8     -- detik tunggu sebelum scan
local HOP        = true  -- aktifkan auto server hop
local HOP_DELAY  = 3
local MIN_PLAYER  = 5     -- min player per server saat hop
local SNIPE_ONLY  = true  -- hanya kirim listing yang harga < RAP
local MIN_RAP     = 1     -- abaikan item dengan RAP 0 / tidak diketahui
local MIN_PROFIT  = 100   -- hanya tampilkan jika profit (RAP - harga) >= nilai ini
                          -- set ke 0 untuk tampilkan semua snipe

-- Filter harga manual per item (nama item = harga maksimal yang mau ditampilkan)
-- Item di sini TIDAK perlu punya RAP — langsung pakai batas harga manual
-- Item yang tidak ada di sini tetap pakai aturan price < RAP seperti biasa
local CUSTOM_FILTERS = {
    ["Megalodon"]      = 500,    -- tampilkan Megalodon jika harga <= 500
    ["Axolotl"]        = 10000,  -- tampilkan Axolotl jika harga <= 10000
    ["Capybara"]       = 200,    -- tampilkan Capybara jika harga <= 200
    ["Penguin"]        = 500,    -- tampilkan Penguin jika harga <= 500

    -- ["Undead Guitar"] = 5000,
    -- ["Holy Rod"]      = 200,
}


-- Item yang HANYA ditampilkan jika punya variant/mutasi
-- (tanpa variant → tidak dikirim ke Discord)
local REQUIRE_VARIANT = {
    ["Megalodon"] = true,   -- Megalodon wajib punya variant
    -- ["Axolotl"] = true,
}

-- Item yang hanya ditampilkan jika tier tertentu
-- (gunakan angka tier: 7 = Secret, 6 = Mythic, 5 = Legendary, dll)
local REQUIRE_TIER = {
    ["Axolotl"] = 7,   -- hanya Axolotl tier 7 (Secret)
    -- ["Megalodon"] = 7,
}

-- Daftar item yang TIDAK ingin ditampilkan (tambah nama di sini saja)

local BLOCKED_ITEMS = (function(list)
    local t = {}
    for _, v in ipairs(list) do t[v:lower()] = true end
    return t
end)({
    "Blob Shark",            "Giant Squid",           "Cryoshade Glider",
    "Gladiator Shark",       "Blackhole Sea Dragon",  "Skeleton Narwhal",
    "Bucket Fish",           "Neonite Fish",           "Fluorivane",
    "Elshark Gran Maja",     "Coney Fish",            "Blobby Shieldfish",
    "Frostbite Leviathan",   "Primal Lobster",        "Emerald Winter Whale",
    "Winter Frost Shark",    "Strawberry Orca",       "1x1x1x1 Comet Shark",
    "Drip Walrus",           "Bonemaw Tyrant",        "Bone Whale",
    "Bloodmoon Whale",       "Classic Glass Octopus", "Ghost Shark",
    "Coral Whale",           "Holiday Turtle Plushie","Fish Fossil",
    "Treasure Crab",         "Violet",                "Aurelion",
    "Elpirate Gran Maja",    "Shark",                 "Great Whale",
    "Queen Crab",            "King Crab",             "Worm Fish",
    "Depthseeker Ray",       "Flame Tyrant",          "Scare",
    "Runic Enchant Stone",
})









-- ────────────────────────────────
--  HTTP
-- ────────────────────────────────
local httpReq = (syn and syn.request)
    or (http and http.request)
    or (fluxus and fluxus.request)
    or http_request
    or request

if not httpReq then warn("[Sniper] HTTP tidak tersedia!"); return end

local function postWebhook(payload, url)
    url = url or WEBHOOK
    if not url or url == "" then return end
    local ok, body = pcall(HttpService.JSONEncode, HttpService, payload)
    if not ok then print("[Webhook] JSON error: " .. tostring(body)); return end
    local ok2, res = pcall(httpReq, {
        Url     = url,
        Method  = "POST",
        Headers = { ["Content-Type"] = "application/json" },
        Body    = body,
    })
    if not ok2 then
        print("[Webhook] Gagal: " .. tostring(res))
    elseif res and res.StatusCode and res.StatusCode >= 400 then
        print(("[Webhook] Error %d: %s"):format(res.StatusCode, tostring(res.Body):sub(1, 80)))
    else
        print("[Webhook] OK " .. tostring(res and res.StatusCode or "?"))
    end
end

local function commas(n)
    if type(n) ~= "number" then return tostring(n or "?") end
    local s = tostring(math.floor(n))
    return (s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
end

-- ────────────────────────────────
--  LOAD MODULES
-- ────────────────────────────────
local Replion, TradeData, ItemUtility

pcall(function() Replion      = require(ReplicatedStorage.Packages.Replion) end)
pcall(function() TradeData    = require(ReplicatedStorage.Shared.Trading.TradeData) end)
pcall(function() ItemUtility  = require(ReplicatedStorage.Shared.ItemUtility) end)

if not Replion then
    warn("[Sniper] Replion belum tersedia saat startup — akan dicoba ulang saat scan.")
end


-- ────────────────────────────────
--  SCAN SEMUA LISTING via Replion
-- ────────────────────────────────
local function scanAllListings()
    local entries = {}

    -- Dapatkan SaleListings replion (semua player)
    print("[Sniper] Menunggu SaleListings replion...")
    local saleListings
    local slOk = pcall(function()
        saleListings = Replion.Client:WaitReplion("SaleListings")
    end)

    if not slOk or not saleListings then
        print("[Sniper] Gagal mendapatkan SaleListings!")
        return entries
    end
    print("[Sniper] SaleListings tersedia.")

    -- Dapatkan RAP replion
    local allRapData = nil
    pcall(function()
        local rapReplion = Replion.Client:WaitReplion("RAP")
        if rapReplion then
            allRapData = rapReplion:Get({"RAPs"})
        end
    end)
    if allRapData then
        print("[Sniper] RAP data tersedia.")
    else
        print("[Sniper] RAP data tidak tersedia, RAP akan di-skip.")
    end

    -- Ambil semua data player
    local allData
    pcall(function() allData = saleListings:Get({"Players"}) end)

    if not allData then
        print("[Sniper] Tidak ada data listing players.")
        return entries
    end

    local playerCount = 0
    for _ in pairs(allData) do playerCount = playerCount + 1 end
    print(("[Sniper] %d player dengan listing ditemukan."):format(playerCount))

    -- Cache untuk item definition
    local itemDefCache = {}

    -- Tier names per itemType (Rod bisa punya nama tier berbeda)
    local tierNames = {
        Fish = {
            [1]="Common", [2]="Uncommon", [3]="Rare",
            [4]="Epic",   [5]="Legendary", [6]="Mythic", [7]="Secret"
        },
        Rod = {
            [1]="Common", [2]="Uncommon", [3]="Rare",
            [4]="Epic",   [5]="Legendary", [6]="Mythic", [7]="Secret"
        },
        -- fallback untuk itemType lain
        Default = {
            [1]="Common", [2]="Uncommon", [3]="Rare",
            [4]="Epic",   [5]="Legendary", [6]="Mythic",
            [7]="Secret", [8]="Divine",    [9]="Celestial"
        },
    }
    local function getTierName(itemType, tier)
        local map = tierNames[itemType] or tierNames.Default
        return map[tier] or ("T" .. tostring(tier))
    end

    for userIdStr, playerData in pairs(allData) do
        local userId = tonumber(userIdStr)
        local sellerPlayer = userId and Players:GetPlayerByUserId(userId)
        local sellerName

        if sellerPlayer then
            -- Hanya DisplayName
            sellerName = sellerPlayer.DisplayName
        else
            sellerName = "ID:" .. userIdStr
        end


        -- Coba dapatkan nama display dari leaderstats jika tersedia
        if sellerPlayer then
            local ls = sellerPlayer:FindFirstChild("leaderstats")
            if ls then
                local rapVal = ls:FindFirstChild("RAP")
                if rapVal then
                    -- Informasi leaderstats tersedia
                end
            end
        end

        -- Scan Booth dan Sign listing
        local containers = {}
        if playerData.Booth then
            table.insert(containers, { source = "Booth", data = playerData.Booth })
        end
        if playerData.Sign then
            table.insert(containers, { source = "Sign", data = playerData.Sign })
        end
        -- Jika tidak ada Booth/Sign, cek key lain di playerData
        if #containers == 0 then
            for k, v in pairs(playerData) do
                if type(v) == "table" then
                    table.insert(containers, { source = k, data = v })
                end
            end
        end

        for _, container in ipairs(containers) do
            for listingId, itemData in pairs(container.data) do
                if type(itemData) ~= "table" then continue end
                if not itemData.Item or not itemData.Price then continue end

                local itemType = itemData.ItemType or "Unknown"
                local itemId   = itemData.Item.Id or itemData.Item.id or listingId

                -- Get item name via ItemUtility
                local ck = tostring(itemType) .. "_" .. tostring(itemId)
                local itemDef = itemDefCache[ck]
                if itemDef == nil then
                    local defOk, defVal = pcall(function()
                        return ItemUtility and ItemUtility.GetItemDataFromItemType(itemType, itemId)
                    end)
                    itemDef = (defOk and defVal) or false
                    itemDefCache[ck] = itemDef
                end

                local itemName = (itemDef and itemDef.Data and itemDef.Data.Name)
                    or tostring(itemId)
                local itemTier = (itemDef and itemDef.Data and itemDef.Data.Tier) or 0
                -- Coba ambil nama tier langsung dari ItemDef, fallback ke tabel
                local tierNameStr = (itemDef and itemDef.Data and (
                    itemDef.Data.TierName or itemDef.Data.Rarity or itemDef.Data.RarityName
                )) or getTierName(itemType, itemTier)
                -- Weight dari Metadata (bukan langsung di Item)
                local meta = itemData.Item.Metadata or {}
                local itemWeight = meta.Weight or meta.weight
                    or itemData.Item.Weight or itemData.Item.weight or ""

                -- Variant dari Metadata.VariantId (confirmed dari debug)
                local itemVariant = ""
                local variantRaw = meta.VariantId or meta.variantId
                    or meta.Variant or meta.variant
                if variantRaw and variantRaw ~= "" and variantRaw ~= 0 then
                    itemVariant = tostring(variantRaw)
                end


                -- Dapatkan RAP dari data replion
                local rap = nil
                if allRapData and itemType and itemId then
                    local rapSection = allRapData[itemType]
                    if rapSection then
                        local rk = itemType .. "/" .. tostring(itemId)
                        local rv = rapSection[rk] or rapSection[tostring(itemId)]
                        if rv and rv ~= -1 then rap = tonumber(rv) end
                    end
                end

                table.insert(entries, {
                    seller     = sellerName,
                    sellerId   = userIdStr,
                    inServer   = sellerPlayer ~= nil,
                    source     = container.source,
                    listingId  = listingId,
                    name       = itemName,
                    itemType   = itemType,
                    itemId     = tostring(itemId),
                    tier       = itemTier,
                    tierName   = tierNameStr,
                    price      = tonumber(itemData.Price) or 0,
                    rap        = rap,
                    weight     = tostring(itemWeight ~= 0 and itemWeight or ""),
                    variant    = itemVariant,
                })
            end
        end
    end

    print(("[Sniper] Total: %d listing ditemukan."):format(#entries))
    return entries
end

-- ────────────────────────────────
--  KIRIM KE DISCORD
-- ────────────────────────────────
local function sendToDiscord(entries)
    local filtered  = {}
    local nonProfit = {}  -- listing harga >= RAP / tidak profit

    for _, e in ipairs(entries) do

        -- Skip item yang diblokir (case-insensitive)
        local nameLower = e.name:lower()
        if BLOCKED_ITEMS[nameLower] then continue end

        -- Skip jika item wajib punya variant tapi tidak ada
        if REQUIRE_VARIANT[e.name] or REQUIRE_VARIANT[e.name:lower()] then
            if not e.variant or e.variant == "" then continue end
        end

        -- Skip jika item wajib tier tertentu tapi tier tidak cocok
        local reqTier = REQUIRE_TIER[e.name] or REQUIRE_TIER[e.name:lower()]
        if reqTier and e.tier ~= reqTier then continue end

        -- Cek custom filter dulu (case-insensitive)
        local customMax = nil
        for itemName, maxPrice in pairs(CUSTOM_FILTERS) do
            if e.name:lower() == itemName:lower() then
                customMax = maxPrice
                break
            end
        end

        if customMax then
            if e.price <= customMax then
                e._filterTag = ("≤%s"):format(commas(customMax))
                table.insert(filtered, e)
            else
                -- Harga melebihi batas custom → masuk non-profit
                if WEBHOOK_INFO ~= "" then
                    table.insert(nonProfit, e)
                end
            end
        else
            if e.rap and e.rap >= MIN_RAP then
                local profit = e.rap - e.price
                if e.price < e.rap and profit >= MIN_PROFIT then
                    e._filterTag = nil
                    table.insert(filtered, e)
                else
                    -- Harga >= RAP atau profit kecil → non-profit
                    if WEBHOOK_INFO ~= "" then
                        table.insert(nonProfit, e)
                    end
                end
            end
        end
    end

    print(("[Discord] %d listing total → %d lolos filter | %d non-profit"):format(#entries, #filtered, #nonProfit))

    if #filtered == 0 and #nonProfit == 0 then
        print("[Discord] Tidak ada listing sama sekali.")
        return
    end

    local hasProfit = #filtered > 0

    -- Sort: custom-filter item di atas, lalu sort profit terbesar
    table.sort(filtered, function(a, b)
        local aCustom = a._filterTag ~= nil
        local bCustom = b._filterTag ~= nil
        if aCustom ~= bCustom then return aCustom end
        -- Profit: jika ada RAP gunakan, jika tidak pakai harga terkecil
        local aProfit = (a.rap and a.rap > 0) and (a.rap - a.price) or -a.price
        local bProfit = (b.rap and b.rap > 0) and (b.rap - b.price) or -b.price
        return aProfit > bProfit
    end)

    -- Pisahkan filtered: yang seller ada di server vs tidak
    local inServer   = {}
    local offServer  = {}
    for _, e in ipairs(filtered) do
        if e.inServer then
            table.insert(inServer, e)
        else
            table.insert(offServer, e)
        end
    end

    local joinUrl  = ("https://www.roblox.com/games/start?placeId=%d&gameInstanceId=%s"):format(placeId, jobId)
    local tpScript = ('game:GetService("TeleportService"):TeleportToPlaceInstance(%d, "%s", game.Players.LocalPlayer)'):format(placeId, jobId)
    local footer   = ("Fish It Sniper v8 | @%s | %s"):format(lp.Name, os.date("%d/%m/%Y %H:%M"))
    local serverStr   = jobId:sub(1, 8)
    local playerCount = #Players:GetPlayers()

    local function buildField(i, e)
        local sourceStr  = e.source ~= "Booth" and (" [" .. e.source .. "]") or ""
        local weightStr = ""
        local wNum = tonumber(e.weight)
        if wNum and wNum > 0 then
            local wDisplay
            if wNum >= 1000000 then
                wDisplay = ("%.1fkt"):format(wNum / 1000000)   -- kiloton
            elseif wNum >= 1000 then
                wDisplay = ("%.2ft"):format(wNum / 1000)       -- ton
            else
                wDisplay = ("%.2fkg"):format(wNum)             -- kg biasa
            end
            weightStr = " | " .. wDisplay
        end

        local variantStr = (e.variant and e.variant ~= "") and ("\n✨ Variant: **" .. e.variant .. "**") or ""

        local rapLine
        local profitSign = 0  -- 0 = unknown, 1 = positive, -1 = negative
        if e._filterTag then
            rapLine = ("Filter: harga ≤ %s T"):format(e._filterTag)
            profitSign = 1
        elseif e.rap and e.rap > 0 then
            local profit = e.rap - e.price
            local pct    = math.floor((e.price / e.rap) * 100)
            if profit >= 0 then
                profitSign = 1
                rapLine = ("RAP: **%s T** | Profit: **+%s T** (%d%%)"):format(
                    commas(e.rap), commas(profit), pct)
            else
                profitSign = -1
                rapLine = ("RAP: **%s T** | Minus: **-%s T** (%d%%)"):format(
                    commas(e.rap), commas(math.abs(profit)), pct)
            end
        else
            rapLine = "RAP: -"
        end

        local icon = profitSign >= 0 and "🔥" or "📉"

        return {
            name  = ("%s #%d %s%s"):format(icon, i, e.name, sourceStr),
            value = (
                "Harga: **%s T**\n" ..
                "%s" ..
                "%s\n" ..
                "%s | 🏷️ %s%s"
            ):format(
                commas(e.price), rapLine, variantStr,
                e.seller, e.tierName, weightStr
            ),
            inline = true,
        }
    end


    local function sendEmbed(title, color, desc, fieldList, webhookUrl)
        for i = 1, #fieldList, 25 do
            local batch = {}
            for j = i, math.min(i + 24, #fieldList) do
                table.insert(batch, fieldList[j])
            end
            local pg = #fieldList > 25
                and (" [" .. math.ceil(i/25) .. "/" .. math.ceil(#fieldList/25) .. "]")
                or ""
            postWebhook({
                username = "Fish It Booth Sniper",
                embeds   = {{
                    title       = title .. pg,
                    description = (i == 1) and desc or nil,
                    color       = color,
                    fields      = batch,
                    footer      = { text = footer },
                }},
            }, webhookUrl)
            if i + 25 <= #fieldList then task.wait(1.2) end
        end
    end

    -- ── Embed 1 & 2: Listing profit (hanya jika ada) ──
    if hasProfit then
        if #inServer > 0 then
            print(("[Discord] Kirim %d listing (in-server)..."):format(#inServer))
            local desc1 = ("Scanner: %s | %d listing | %d players | [Join Server](%s)\n```\n%s\n```"):format(lp.DisplayName, #inServer, playerCount, joinUrl, tpScript)
            local fields1 = {}
            for i, e in ipairs(inServer) do
                table.insert(fields1, buildField(i, e))
            end
            sendEmbed("Plaza Sniper", 0xF4A460, desc1, fields1)
        end

        if #offServer > 0 then
            task.wait(1)
            print(("[Discord] Kirim %d listing (off-server)..."):format(#offServer))
            local desc2 = ("Scanner: %s | %d listing | %d players | [Join Server](%s)\n```\n%s\n```"):format(lp.DisplayName, #offServer, playerCount, joinUrl, tpScript)
            local fields2 = {}
            for i, e in ipairs(offServer) do
                table.insert(fields2, buildField(i, e))
            end
            sendEmbed("Plaza Sniper", 0x5865F2, desc2, fields2)
        end
    else
        print("[Discord] Tidak ada listing profit — skip embed profit.")
    end


    -- ── Embed 3: Non-profit → WEBHOOK_INFO ──
    if #nonProfit > 0 and WEBHOOK_INFO ~= "" then
        task.wait(1)
        -- Sort: Secret (7) → Mythic (6) → lainnya, tiap grup profit terbesar dulu
        local tierPriority = { [7] = 1, [6] = 2 }  -- Secret = rank 1, Mythic = rank 2
        table.sort(nonProfit, function(a, b)
            local aRank = tierPriority[a.tier] or 3
            local bRank = tierPriority[b.tier] or 3
            if aRank ~= bRank then return aRank < bRank end
            -- Tier sama → profit terbesar dulu
            local aP = (a.rap or 0) - a.price
            local bP = (b.rap or 0) - b.price
            return aP > bP
        end)

        -- Ambil 25 teratas saja
        local top25 = {}
        for i = 1, math.min(25, #nonProfit) do
            table.insert(top25, nonProfit[i])
        end
        print(("[Discord] Kirim %d (dari %d) non-profit ke WEBHOOK_INFO..."):format(#top25, #nonProfit))
        local desc3 = ("Scanner: %s | %d listing | %d players | [Join Server](%s)\n```\n%s\n```"):format(lp.DisplayName, #top25, playerCount, joinUrl, tpScript)
        local fields3 = {}
        for i, e in ipairs(top25) do
            table.insert(fields3, buildField(i, e))
        end
        sendEmbed("Non Profit", 0x95a5a6, desc3, fields3, WEBHOOK_INFO)
    end


    print(("[Sniper] Selesai: %d profit + %d non-profit listing"):format(#entries - #nonProfit, #nonProfit))
end


-- ────────────────────────────────
--  SERVER HOP
-- ────────────────────────────────
local function hopServer()
    print("[HOP] Mencari server...")
    local list, cursor = {}, ""
    for _ = 1, 5 do
        local url = ("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Desc&limit=100&cursor=%s"):format(placeId, cursor)
        local ok, res = pcall(httpReq, { Url = url, Method = "GET" })
        if not ok or not res then break end
        local ok2, data = pcall(HttpService.JSONDecode, HttpService, res.Body or "")
        if not ok2 or not data or not data.data then break end
        for _, s in ipairs(data.data) do
            if s.id and s.id ~= jobId and (s.playing or 0) >= MIN_PLAYER then
                table.insert(list, { id = s.id, players = s.playing or 0 })
            end
        end
        cursor = data.nextPageCursor or ""
        if cursor == "" or #list >= 50 then break end
    end

    if #list == 0 then
        print("[HOP] Tidak ada server. Retry 30s...")
        task.wait(30); return hopServer()
    end

    table.sort(list, function(a, b) return a.players > b.players end)
    print(("[HOP] %d server tersedia. Masuk server (%d players)"):format(#list, list[1].players))

    for _, srv in ipairs(list) do
        task.wait(HOP_DELAY)
        local failed, conn = false, nil
        pcall(function()
            conn = TeleportService.TeleportInitFailed:Connect(function(p)
                if p == lp then failed = true end
            end)
        end)
        local ok = pcall(TeleportService.TeleportToPlaceInstance, TeleportService, placeId, srv.id, lp)
        if ok then
            task.wait(15)
            if conn then pcall(function() conn:Disconnect() end) end
            if not failed then print("[HOP] Berhasil!"); task.wait(30); return end
        end
        if conn then pcall(function() conn:Disconnect() end) end
    end

    print("[HOP] Semua gagal. Retry 30s...")
    task.wait(30); hopServer()
end

-- ────────────────────────────────
--  GUI START / STOP
-- ────────────────────────────────
local CoreGui        = game:GetService("CoreGui")
local TweenService   = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local _sniperRunning = false
local _sniperThread  = nil
local _hopThread     = nil

-- Hapus GUI lama jika ada
if CoreGui:FindFirstChild("FishItSniperHUD") then
    CoreGui.FishItSniperHUD:Destroy()
end

local guiParent = pcall(function() return CoreGui.Name end) and CoreGui or lp:WaitForChild("PlayerGui")

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "FishItSniperHUD"
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.DisplayOrder = 999
ScreenGui.Parent = guiParent

-- Main frame
local Frame = Instance.new("Frame")
Frame.Name = "HUD"
Frame.Size = UDim2.new(0, 200, 0, 90)
Frame.Position = UDim2.new(0, 20, 0.5, -45)
Frame.BackgroundColor3 = Color3.fromRGB(14, 14, 20)
Frame.BorderSizePixel = 0
Frame.Parent = ScreenGui
Instance.new("UICorner", Frame).CornerRadius = UDim.new(0, 10)
local stroke = Instance.new("UIStroke")
stroke.Thickness = 1.5
stroke.Color = Color3.fromRGB(80, 80, 120)
stroke.Transparency = 0.4
stroke.Parent = Frame

-- Title bar
local TitleBar = Instance.new("Frame")
TitleBar.Size = UDim2.new(1, 0, 0, 28)
TitleBar.BackgroundColor3 = Color3.fromRGB(10, 10, 16)
TitleBar.BorderSizePixel = 0
TitleBar.Parent = Frame
local tc = Instance.new("UICorner")
tc.CornerRadius = UDim.new(0, 10)
tc.Parent = TitleBar
-- Fix bottom of title bar
local fix = Instance.new("Frame")
fix.Size = UDim2.new(1, 0, 0, 10)
fix.Position = UDim2.new(0, 0, 1, -10)
fix.BackgroundColor3 = Color3.fromRGB(10, 10, 16)
fix.BorderSizePixel = 0
fix.Parent = TitleBar

local TitleLabel = Instance.new("TextLabel")
TitleLabel.Size = UDim2.new(1, -8, 1, 0)
TitleLabel.Position = UDim2.new(0, 8, 0, 0)
TitleLabel.BackgroundTransparency = 1
TitleLabel.Text = "🎣 Fish It Sniper"
TitleLabel.TextColor3 = Color3.fromRGB(200, 200, 255)
TitleLabel.Font = Enum.Font.GothamBold
TitleLabel.TextSize = 12
TitleLabel.TextXAlignment = Enum.TextXAlignment.Left
TitleLabel.Parent = TitleBar

-- Accent line
local accentLine = Instance.new("Frame")
accentLine.Size = UDim2.new(1, 0, 0, 2)
accentLine.Position = UDim2.new(0, 0, 1, 0)
accentLine.BackgroundColor3 = Color3.fromRGB(88, 130, 255)
accentLine.BorderSizePixel = 0
accentLine.Parent = TitleBar
local grad = Instance.new("UIGradient")
grad.Color = ColorSequence.new(Color3.fromRGB(88,130,255), Color3.fromRGB(255,200,80))
grad.Parent = accentLine

-- Status label
local StatusLabel = Instance.new("TextLabel")
StatusLabel.Size = UDim2.new(1, -12, 0, 16)
StatusLabel.Position = UDim2.new(0, 6, 0, 32)
StatusLabel.BackgroundTransparency = 1
StatusLabel.Text = "⏹ Idle"
StatusLabel.TextColor3 = Color3.fromRGB(140, 140, 160)
StatusLabel.Font = Enum.Font.Gotham
StatusLabel.TextSize = 11
StatusLabel.TextXAlignment = Enum.TextXAlignment.Left
StatusLabel.Parent = Frame

-- START / STOP button
local Btn = Instance.new("TextButton")
Btn.Size = UDim2.new(1, -16, 0, 30)
Btn.Position = UDim2.new(0, 8, 0, 52)
Btn.BackgroundColor3 = Color3.fromRGB(40, 180, 80)
Btn.Text = "▶  START"
Btn.Font = Enum.Font.GothamBold
Btn.TextSize = 13
Btn.TextColor3 = Color3.new(1, 1, 1)
Btn.AutoButtonColor = false
Btn.BorderSizePixel = 0
Btn.Parent = Frame
Instance.new("UICorner", Btn).CornerRadius = UDim.new(0, 6)

local function setBtn(running)
    if running then
        Btn.Text = "⏹  STOP"
        Btn.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
        stroke.Color = Color3.fromRGB(200, 50, 50)
        StatusLabel.TextColor3 = Color3.fromRGB(100, 220, 120)
    else
        Btn.Text = "▶  START"
        Btn.BackgroundColor3 = Color3.fromRGB(40, 180, 80)
        stroke.Color = Color3.fromRGB(80, 80, 120)
        StatusLabel.TextColor3 = Color3.fromRGB(140, 140, 160)
        StatusLabel.Text = "⏹ Idle"
    end
end

-- Hover effects
Btn.MouseEnter:Connect(function()
    TweenService:Create(Btn, TweenInfo.new(0.15), {
        BackgroundColor3 = _sniperRunning
            and Color3.fromRGB(230, 70, 70)
            or  Color3.fromRGB(60, 210, 100)
    }):Play()
end)
Btn.MouseLeave:Connect(function()
    TweenService:Create(Btn, TweenInfo.new(0.15), {
        BackgroundColor3 = _sniperRunning
            and Color3.fromRGB(200, 50, 50)
            or  Color3.fromRGB(40, 180, 80)
    }):Play()
end)

-- Drag logic
do
    local dragging, dragStart, startPos
    TitleBar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = Frame.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                end
            end)
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch) then
            local delta = input.Position - dragStart
            Frame.Position = UDim2.new(
                startPos.X.Scale, startPos.X.Offset + delta.X,
                startPos.Y.Scale, startPos.Y.Offset + delta.Y
            )
        end
    end)
end

-- ────────────────────────────────
--  SNIPER RUNNER
-- ────────────────────────────────
local function runSniper()
    StatusLabel.Text = ("⏳ Tunggu %ds..."):format(SCAN_WAIT)
    print("[Sniper] Fish It Plaza Booth Sniper v8.0")
    print("[Sniper] Scanner : " .. lp.Name)
    print("[Sniper] Server  : " .. jobId:sub(1, 12))

    -- Pastikan Replion sudah tersedia (retry sampai 30 detik)
    if not Replion then
        StatusLabel.Text = "⏳ Tunggu Replion..."
        for i = 1, 30 do
            if not _sniperRunning then return end
            pcall(function() Replion = require(ReplicatedStorage.Packages.Replion) end)
            if Replion then break end
            task.wait(1)
        end
        if not Replion then
            StatusLabel.Text = "❌ Replion gagal load!"
            warn("[Sniper] Replion tidak tersedia. Pastikan di Trade Plaza!")
            _sniperRunning = false
            setBtn(false)
            return
        end
    end

    -- Tunggu sebelum scan
    for i = SCAN_WAIT, 1, -1 do
        if not _sniperRunning then return end
        StatusLabel.Text = ("⏳ Scan dalam %ds..."):format(i)
        task.wait(1)
    end

    if not _sniperRunning then return end

    -- Scan listing
    StatusLabel.Text = "🔍 Scanning..."
    print("[Sniper] Memulai scan listing...")
    local entries = scanAllListings()

    if not _sniperRunning then return end

    -- Kirim ke Discord
    if #entries > 0 then
        StatusLabel.Text = ("📨 Kirim %d listing..."):format(#entries)
        sendToDiscord(entries)
    else
        StatusLabel.Text = "⚠️ Tidak ada listing"
        print("[Sniper] Tidak ada listing ditemukan.")
    end

    if not _sniperRunning then return end

    -- Server hop
    if HOP then
        StatusLabel.Text = "🔀 Server hop..."
        print("[Sniper] Pindah server...")
        task.wait(2)

        -- hop loop dengan cek flag
        local function hopLoop()
            while _sniperRunning do
                StatusLabel.Text = "🔍 Cari server..."
                print("[HOP] Mencari server...")
                local list, cursor = {}, ""
                for _ = 1, 5 do
                    if not _sniperRunning then return end
                    local url = ("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Desc&limit=100&cursor=%s"):format(placeId, cursor)
                    local ok, res = pcall(httpReq, { Url = url, Method = "GET" })
                    if not ok or not res then break end
                    local ok2, data = pcall(HttpService.JSONDecode, HttpService, res.Body or "")
                    if not ok2 or not data or not data.data then break end
                    for _, s in ipairs(data.data) do
                        if s.id and s.id ~= jobId and (s.playing or 0) >= MIN_PLAYER then
                            table.insert(list, { id = s.id, players = s.playing or 0 })
                        end
                    end
                    cursor = data.nextPageCursor or ""
                    if cursor == "" or #list >= 50 then break end
                end

                if #list == 0 then
                    StatusLabel.Text = "❌ Tidak ada server"
                    if not _sniperRunning then return end
                    task.wait(30)
                else
                    -- Shuffle acak (Fisher-Yates) — tidak fokus ke server penuh saja
                    for i = #list, 2, -1 do
                        local j = math.random(1, i)
                        list[i], list[j] = list[j], list[i]
                    end
                    local picked = list[1]
                    StatusLabel.Text = ("🔀 Hop random → %d players"):format(picked.players)
                    print(("[HOP] Pilih server random: %s (%d players)"):format(picked.id:sub(1,8), picked.players))

                    local failed, conn = false, nil
                    pcall(function()
                        conn = TeleportService.TeleportInitFailed:Connect(function(p)
                            if p == lp then failed = true end
                        end)
                    end)
                    local ok = pcall(TeleportService.TeleportToPlaceInstance, TeleportService, placeId, picked.id, lp)
                    if ok then
                        task.wait(15)
                        if conn then pcall(function() conn:Disconnect() end) end
                        if not failed then return end
                    end
                    if conn then pcall(function() conn:Disconnect() end) end
                    task.wait(5)
                end

            end
        end

        hopLoop()
    end
end

-- ────────────────────────────────
--  BUTTON CLICK
-- ────────────────────────────────
Btn.MouseButton1Click:Connect(function()
    if _sniperRunning then
        -- STOP
        _sniperRunning = false
        if _sniperThread then
            task.cancel(_sniperThread)
            _sniperThread = nil
        end
        setBtn(false)
        print("[Sniper] Dihentikan oleh user.")
    else
        -- START
        _sniperRunning = true
        setBtn(true)
        _sniperThread = task.spawn(function()
            local ok, err = pcall(runSniper)
            if not ok then
                StatusLabel.Text = "❌ Error!"
                warn("[Sniper] Error: " .. tostring(err))
            end
            if _sniperRunning then
                _sniperRunning = false
                setBtn(false)
            end
        end)
        print("[Sniper] Dimulai.")
    end
end)

print("[Sniper] GUI loaded — auto start dalam 1s...")

-- AUTO START
task.delay(1, function()
    _sniperRunning = true
    setBtn(true)
    _sniperThread = task.spawn(function()
        local ok, err = pcall(runSniper)
        if not ok then
            StatusLabel.Text = "❌ Error!"
            warn("[Sniper] Error: " .. tostring(err))
        end
        if _sniperRunning then
            _sniperRunning = false
            setBtn(false)
        end
    end)
    print("[Sniper] Auto-start!")
end)
