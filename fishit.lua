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
local WEBHOOK    = "https://discord.com/api/webhooks/1511803435706617907/ISbwuFnRw68XU2qvSgZ3IVCmxCn01jD3hROs_jPDiraWruyBsVzVsIcJF7m7Vy070a6e"
local SCAN_WAIT  = 8     -- detik tunggu sebelum scan
local HOP        = true  -- aktifkan auto server hop
local HOP_DELAY  = 3
local MIN_PLAYER  = 5     -- min player per server saat hop
local SNIPE_ONLY  = true  -- hanya kirim listing yang harga < RAP
local MIN_RAP     = 1     -- abaikan item dengan RAP 0 / tidak diketahui

-- Filter harga manual per item (nama item = harga maksimal yang mau ditampilkan)
-- Item di sini TIDAK perlu punya RAP — langsung pakai batas harga manual
-- Item yang tidak ada di sini tetap pakai aturan price < RAP seperti biasa
local CUSTOM_FILTERS = {
    ["Megalodon"]      = 500,    -- tampilkan Megalodon jika harga <= 500
    ["Axolotl"]      = 2000,
    -- ["Undead Guitar"] = 5000, -- contoh: Undead Guitar di bawah 5000
    -- ["Holy Rod"]      = 200,  -- contoh: Holy Rod di bawah 200
}



-- ────────────────────────────────
--  HTTP
-- ────────────────────────────────
local httpReq = (syn and syn.request)
    or (http and http.request)
    or (fluxus and fluxus.request)
    or http_request
    or request

if not httpReq then warn("[Sniper] HTTP tidak tersedia!"); return end

local function postWebhook(payload)
    local ok, body = pcall(HttpService.JSONEncode, HttpService, payload)
    if not ok then print("[Webhook] JSON error: " .. tostring(body)); return end
    local ok2, res = pcall(httpReq, {
        Url     = WEBHOOK,
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
    warn("[Sniper] Replion tidak tersedia! Pastikan dijalankan di Trade Plaza.")
    return
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

    local tierNames = {
        [1]="Common", [2]="Uncommon", [3]="Rare",
        [4]="Epic", [5]="Legendary", [6]="Mythic", [7]="Secret"
    }

    for userIdStr, playerData in pairs(allData) do
        local userId = tonumber(userIdStr)
        local sellerPlayer = userId and Players:GetPlayerByUserId(userId)
        local sellerName

        if sellerPlayer then
            sellerName = sellerPlayer.Name
        else
            -- Player tidak ada di server ini (listing dari server lain/database)
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
                local itemWeight = itemData.Item.Weight or itemData.Item.weight or ""

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
                    tierName   = tierNames[itemTier] or ("T" .. itemTier),
                    price      = tonumber(itemData.Price) or 0,
                    rap        = rap,
                    weight     = tostring(itemWeight ~= 0 and itemWeight or ""),
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
    local filtered = {}

    for _, e in ipairs(entries) do

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
            end
        else
            if e.rap and e.rap >= MIN_RAP and e.price < e.rap then
                e._filterTag = nil
                table.insert(filtered, e)
            end
        end
    end

    print(("[Discord] %d listing total → %d lolos filter"):format(#entries, #filtered))

    if #filtered == 0 then
        print("[Discord] Tidak ada listing yang cocok filter di server ini.")
        return
    end

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

    entries = filtered

    if #entries == 0 then
        print("[Discord] Tidak ada listing untuk dikirim.")
        return
    end

    -- Pisahkan: yang seller ada di server vs tidak
    local inServer   = {}
    local offServer  = {}
    for _, e in ipairs(entries) do
        if e.inServer then
            table.insert(inServer, e)
        else
            table.insert(offServer, e)
        end
    end

    local joinUrl  = ("https://www.roblox.com/games/start?placeId=%d&gameInstanceId=%s"):format(placeId, jobId)
    local tpScript = ('game:GetService("TeleportService"):TeleportToPlaceInstance(%d, "%s", game.Players.LocalPlayer)'):format(placeId, jobId)
    local footer   = ("Fish It Sniper v8 | @%s | %s"):format(lp.Name, os.date("%d/%m/%Y %H:%M"))
    local serverStr = jobId:sub(1, 8)

    local function buildField(i, e)
        local sourceStr = e.source ~= "Booth" and (" [" .. e.source .. "]") or ""
        local weightStr = (e.weight and e.weight ~= "" and e.weight ~= "0")
            and (" | " .. e.weight .. "kg") or ""

        local rapLine
        if e._filterTag then
            rapLine = ("📌 Filter manual: harga ≤ %s T"):format(e._filterTag)
        elseif e.rap and e.rap > 0 then
            local profit = e.rap - e.price
            local pct    = math.floor((e.price / e.rap) * 100)
            rapLine = ("📊 RAP: **%s T** | Profit: **+%s T** (%d%%)"):format(
                commas(e.rap), commas(profit), pct)
        else
            rapLine = "📊 RAP: -"
        end

        return {
            name  = ("🔥 #%d %s%s"):format(i, e.name, sourceStr),
            value = (
                "💰 Harga: **%s T**\n" ..
                "%s\n" ..
                "👤 %s | 🏷️ %s%s"
            ):format(
                commas(e.price), rapLine,
                e.seller, e.tierName, weightStr
            ),
            inline = true,
        }
    end

    local function sendEmbed(title, color, desc, fieldList)
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
            })
            if i + 25 <= #fieldList then task.wait(1.2) end
        end
    end

    -- ── Embed 1: Listing dari player yang ada di server ini ──
    if #inServer > 0 then
        print(("[Discord] Kirim %d listing (in-server)..."):format(#inServer))
        local desc1 = ("**[Fish It] Plaza Listings** — Server `%s`\nScanner: @%s | **%d listing aktif**\n[Join](%s)\n```\n%s\n```"):format(
            serverStr, lp.Name, #inServer, joinUrl, tpScript)
        local fields1 = {}
        for i, e in ipairs(inServer) do
            table.insert(fields1, buildField(i, e))
        end
        sendEmbed("🏪 Listing (Server Ini)", 0xF4A460, desc1, fields1)
    end

    -- ── Embed 2: Listing dari player yang tidak ada di server ini ──
    if #offServer > 0 then
        task.wait(1)
        print(("[Discord] Kirim %d listing (off-server/database)..."):format(#offServer))
        local desc2 = ("**[Fish It] Off-Server Listings** — Server `%s`\nScanner: @%s | **%d listing** dari player tidak ada di server ini\n[Join](%s)"):format(
            serverStr, lp.Name, #offServer, joinUrl)
        local fields2 = {}
        for i, e in ipairs(offServer) do
            table.insert(fields2, buildField(i, e))
        end
        sendEmbed("👤 Listing (Database/Off-Server)", 0x5865F2, desc2, fields2)
    end

    print(("[Sniper] Selesai: %d in-server + %d off-server listing"):format(#inServer, #offServer))
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
--  MAIN
-- ────────────────────────────────
print("[Sniper] Fish It Plaza Booth Sniper v8.0")
print("[Sniper] Scanner : " .. lp.Name)
print("[Sniper] Server  : " .. jobId:sub(1, 12))
print("[Sniper] Tunggu  : " .. SCAN_WAIT .. "s...")

task.wait(SCAN_WAIT)

-- Scan semua listing via Replion
print("[Sniper] Memulai scan listing...")
local entries = scanAllListings()

-- Kirim ke Discord
if #entries > 0 then
    sendToDiscord(entries)
else
    print("[Sniper] Tidak ada listing ditemukan di server ini.")
end

-- Server hop
if HOP then
    print("[Sniper] Pindah server...")
    task.wait(2)
    hopServer()
end
