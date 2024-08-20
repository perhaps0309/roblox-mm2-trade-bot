local sendOrderSuccess = true -- // When the user completes the order
local sendOrderFailure = false -- // Could be for if the user cancels or doesn't accept the order
local sendOrderStarted = true -- // When the user accepts the trade

local tagHandler = ""
local secretKey = """
local totalJumps = 3
local queueTimeout = 30; -- // Amount of seconds to wait before moving to the next order, if the order is not completed
local orderWebhook = ""
local orderCacheFile = "MM2_Cache.json"

local productIdLink = "https://productIds.json"

-- // ETA Estimation

local averageTradeTime = 20 -- // Average trade time in seconds

-- // Variables

local getOrdersLink = tagHandler.."?getShopifyOrders=true&secretKey="..secretKey

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local localPlayer = Players.LocalPlayer

local InventoryModule = ReplicatedStorage.Modules.InventoryModule
local SayMessageRequest = ReplicatedStorage.DefaultChatSystemChatEvents.SayMessageRequest

local tradeModule = ReplicatedStorage.Trade
local offerItem = game:GetService("ReplicatedStorage"):WaitForChild("Trade"):WaitForChild("OfferItem")
local acceptTrade = game:GetService("ReplicatedStorage"):WaitForChild("Trade"):WaitForChild("AcceptTrade")
local declineTrade = game:GetService("ReplicatedStorage"):WaitForChild("Trade"):WaitForChild("DeclineTrade")
local cancelRequest = game:GetService("ReplicatedStorage"):WaitForChild("Trade"):WaitForChild("CancelRequest") -- // for when the request is timed out

local productIds = request({Url = productIdLink})
productIds = game:GetService("HttpService"):JSONDecode(productIds.Body)

-- // Code 

local function orderCacheInit()
    if isfile(orderCacheFile) then 
        local fileData = readfile(orderCacheFile)
        local decodedData = game.HttpService:JSONDecode(fileData)

        return decodedData
    else 
        writefile(orderCacheFile, game.HttpService:JSONEncode({}))
        return {}
    end
end

local function orderCacheUpdate(orderData)
    local fileData = readfile(orderCacheFile)
    local decodedData = game.HttpService:JSONDecode(fileData)

    decodedData[orderData.id] = orderData

    writefile(orderCacheFile, game.HttpService:JSONEncode(decodedData))
end

orderCacheInit()

local function searchInventory(inventoryTable, searchKey, searchValue)
    -- // Search the inventory for a table with a key called "Amount"
    searchKey = searchKey or "Amount"
    searchValue = searchValue or false

    local allItems = {}
    for i, v in pairs(inventoryTable) do 
        if typeof(v) == "table" and v[searchKey] then 
            if not searchValue then allItems[v.Name] = v[searchKey] 
            else 
                allItems[v[searchKey]] = v[searchValue]
            end 
        elseif type(v) == "table" then 
            local newItems = searchInventory(v, searchKey, searchValue)
            for i2, v2 in pairs(newItems) do 
                allItems[i2] = v2
            end
        end
    end

    return allItems
end

local function getInventory(searchKey, searchValue)
    local moduleData = require(InventoryModule)
    moduleData = moduleData.MyInventory.Data 
    
    local allItems = searchInventory(moduleData, searchKey, searchValue)
    return allItems
end

local function getOrders() 
    local newRequest = request({Url = getOrdersLink, Method = "GET"})
    if newRequest.StatusCode ~= 200 then -- // bro how 
        return false
    end
    
    local allOrders = game.HttpService:JSONDecode(newRequest.Body)
    return allOrders.data 
end 

local function markOrderComplete(orderId)
    local newRequest = request({Url = tagHandler.."?setOrderComplete="..orderId})
    if newRequest.StatusCode ~= 200 then -- // bro how 
        return false
    end

    return true
end

local titleExtensions = {
    ["notenoughstock"] = "Out Of Stock!",
    ["playerleft"] = "Player Left!",
    ["cancelrequest"] = "Player canceled the request to trade!",
    ["timeout"] = "Trade request timed out!"
}

local errorDescriptions = {
    ["notenoughstock"] = "Account does not have enough stock to complete order.",
    ["playerleft"] = "Player left the game before completing the order.",
    ["cancelrequest"] = "Player canceled the request to trade.",
    ["timeout"] = "Trade request timed out."
}

local function sendEmbed(robloxUsername, embedType, timeTaken, orderItems, orderTotal, errorCode) -- // success, failure, started
    robloxUsername = robloxUsername or "Unknown"
    orderTotal = orderTotal or "0.00?"
    local playerInventory = getInventory("DataID", "Amount")
    local createdFields = {}
    if embedType == "success" or embedType == "started" then 
        for i, v in pairs(orderItems) do 
            local currentStock = playerInventory[i] or 0
            table.insert(createdFields, {
                ["name"] = i.." ("..tostring(v)..")",
                ["value"] = embedType == "success" and "Old Stock: "..currentStock + v.."\nNew Stock: "..currentStock or "Current Stock: "..currentStock,
                ["inline"] = true
            })
        end
    else 
        for i, v in pairs(orderItems) do 
            if not playerInventory[i] or playerInventory[i] < v then 
                local currentStock = playerInventory[i] or 0
                table.insert(createdFields, {
                    ["name"] = i.." ("..tostring(v)..")",
                    ["value"] = "Current Stock: "..currentStock.."\nNeeded Stock: "..v - currentStock,
                    ["inline"] = true
                })
            end
        end
    end 

    local embedTitle = embedType == "success" and "Order Completed" or embedType == "failure" and "Order Failed" or embedType == "started" and "Order Started" or "Unknown"
    if embedType == "success" or embedType == "started" then 
        embedTitle = embedTitle .. " (@" .. robloxUsername .. ") - $" .. orderTotal
    else 
        embedTitle = embedTitle .. " (@" .. robloxUsername .. ") - " .. (titleExtensions[errorCode] or "Unknown")
    end

    request({
        Url = orderWebhook,
        Method = "POST",
        Headers = {
            ["Content-Type"] = "application/json"
        },
        Body = game.HttpService:JSONEncode({
            ["embeds"] = {{
                    ["title"] = embedTitle,
                    ["description"] = embedType == "success" and "Successfully completed in "..tostring(timeTaken).."s of user joining the server." or (embedType == "failure" and errorDescriptions[errorCode] or embedType == "failure" and "Failed to complete order.") or embedType == "started" and "Started the order in "..tostring(timeTaken).."s of user joining the server.",
                    ["color"] = embedType == "success" and 65280 or embedType == "failure" and 16711680 or embedType == "started" and 16776960,
                    ["fields"] = createdFields
                }
            }
        })
    })
end

local function hasStock(orderItems)
    local playerInventory = getInventory("DataID", "Amount")

    local outOfStockItems = {}
    for i, v in pairs(orderItems) do 
        if not playerInventory[i] or playerInventory[i] < v then 
            table.insert(outOfStockItems, i)
        end
    end

    if #outOfStockItems > 0 then 
        return false, outOfStockItems
    else 
        return true
    end
end

local awaitingTrades = {}
local currentTrade;
local function handleTrade(processItems, currentTrade)
    local playerObject = currentTrade.player

    tradeModule.SendRequest:InvokeServer(playerObject)

    local playerName = playerObject.Name:lower()
    local justSent = tick()
    repeat task.wait() until not awaitingTrades[playerName] or tick() - justSent >= queueTimeout or awaitingTrades[playerName].acceptTrade == true or awaitingTrades[playerName].declineRequest == true
    if not awaitingTrades[playerName] or not awaitingTrades[playerName].acceptTrade then
        awaitingTrades[currentTrade.player.Name:lower()] = nil

        if tick() - justSent >= queueTimeout then 
            sendEmbed(currentTrade.player.Name, "failure", 0, currentTrade.order.items, tonumber(currentTrade.order.orderTotal), "timeout")
        end 

        return false;
    end 

    local sendingItems = {}
    for DataID, v in pairs(processItems) do  
        for i2 = 1, v do 
            print("Sending "..tostring(DataID).."(" .. tostring(v) .. ") to "..tostring(playerObject.Name))
            offerItem:FireServer(DataID, "Weapons")

            if not currentTrade.sentItems then 
                currentTrade.sentItems = {}
            end
        end

        currentTrade.sentItems[DataID] = v
    end

    task.wait(6.5)

    warn("Accepted trade.")
    acceptTrade:FireServer()

    justSent = tick()
    local tradeAccepted = tick()
    repeat task.wait() 
        if tradeAccepted and tick() - tradeAccepted >= 6 then 
            acceptTrade:FireServer()
            tradeAccepted = tick()
        end
    until not awaitingTrades[playerName] or awaitingTrades[playerName].declineTrade == true or awaitingTrades[playerName].tradeCompleted == true or tick() - justSent >= queueTimeout
    if not awaitingTrades[playerName] or not awaitingTrades[playerName].tradeCompleted then 
        awaitingTrades[currentTrade.player.Name:lower()] = nil

        if tick() - justSent >= queueTimeout then 
            declineTrade:FireServer()
            sendEmbed(currentTrade.player.Name, "failure", 0, currentTrade.order.items, tonumber(currentTrade.order.orderTotal), "timeout")
        end 

        return false;
    end

    awaitingTrades[currentTrade.player.Name:lower()].tradeCompleted = false 
    awaitingTrades[currentTrade.player.Name:lower()].acceptTrade = false

    markOrderComplete(currentTrade.order.orderId)
    for i, v in pairs(sendingItems) do 
        table.insert(currentTrade.sentItems, i)
    end 

    return true;
end

local function processQueue()
    local currentQueuePosition = 0
    for i, v in pairs(awaitingTrades) do 
        currentQueuePosition = currentQueuePosition + 1
    end

    if currentQueuePosition == 0 then return end

    currentTrade = awaitingTrades[next(awaitingTrades)]
    local orderItems = currentTrade.order.items 
    
    local items = {} -- For item titles
    for title in pairs(orderItems) do 
        table.insert(items, title)
    end

    local tradesNeeded = math.round(#items / 4 + 0.5)

    local batchSize = 4
    local totalItems = #items
    local batchStart = 1

    print("Starting trade for "..currentTrade.player.Name.." with "..tostring(tradesNeeded).." trades needed.")

    local completedTrades = 0
    while batchStart <= totalItems do
        local nextItems = {}
        
        for i2 = batchStart, math.min(batchStart + batchSize - 1, totalItems) do
            local itemTitle = items[i2]
            nextItems[itemTitle] = orderItems[itemTitle]
            warn("Adding "..itemTitle.." to nextItems")
        end

        warn("batchStart:", batchStart, math.min(batchStart + batchSize - 1, totalItems))

        if next(nextItems) then  -- Check if nextItems isn't empty
            local didTrade = handleTrade(nextItems, currentTrade)
            if not didTrade then break end

            completedTrades = completedTrades + 1
        end
        
        batchStart = batchStart + batchSize
    end

    if completedTrades == tradesNeeded then 
        sendEmbed(currentTrade.player.Name, "success", tick() - currentTrade.joinTime, currentTrade.order.items, tonumber(currentTrade.order.orderTotal))

        SayMessageRequest:FireServer(currentTrade.player.Name.." - The trade has completed, thank you for your purchase!", "normalchat")
        awaitingTrades[currentTrade.player.Name:lower()] = nil

        -- // remove order from cache
        local currentCache = orderCacheInit()
        currentCache[currentTrade.order.orderId] = nil

        writefile(orderCacheFile, game.HttpService:JSONEncode(currentCache))
    else 
        -- // remove sent items from cache
        if currentTrade.sentItems then 
            local currentCache = orderCacheInit()
            for i, v in pairs(currentTrade.sentItems) do 
                currentCache[i] = nil
            end

            writefile(orderCacheFile, game.HttpService:JSONEncode(currentCache))
        end
    end 

    awaitingTrades[currentTrade.player.Name:lower()] = nil
    currentTrade = nil
    processQueue()   
end

local function confirmedActivity(dataTable)
    local Player = dataTable.player
    local order = dataTable.order

    local enoughItems = hasStock(order.items)
    if enoughItems == false then 
        sendEmbed(Player.Name, "failure", 0, order.items, tonumber(order.orderTotal), "notenoughstock")
        SayMessageRequest:FireServer(Player.Name.." - Sorry, we do not have enough stock to complete your order. Please create a ticket in our server!", "normalchat")
        return 
    end

    local currentQueuePosition = 0 
    local ETA = 0;
    for i2, v2 in pairs(awaitingTrades) do 
        currentQueuePosition = currentQueuePosition + 1
    end

    -- // loop through all orders, divide amount of items by 4(each trade can have 4 unique items, but can have more than 4 of the same item)

    if currentQueuePosition > 0 then 
        for i2, v2 in pairs(awaitingTrades) do 
            if v2.player == Player then continue end

            local itemAmount = 0
            for i3, v3 in pairs(v2.order.items) do 
                itemAmount = itemAmount + v3
            end
            
            ETA = ETA + (itemAmount / 4) * averageTradeTime
        end
    end

    local ETAMessage = ETA > 0 and " - Estimated Time: "..tostring(ETA).."s" or ""

    SayMessageRequest:FireServer(Player.Name.." - Your order has been put into queue #"..tostring(currentQueuePosition).." of #"..tostring(currentQueuePosition) .. ETAMessage, "normalchat")

    if not currentTrade then 
        processQueue()
    end
end

local function handleOrder(order, Player, isPending)
    if awaitingTrades[Player.Name:lower()] then return end

    awaitingTrades[Player.Name:lower()] = {sentMessage = false, username = order.username, order = isPending and order.order or order, player = Player, jumpCount = 0, joinTime = tick(), confirmedActivity = false, sentTrade = tick(), acceptTrade = false, declineTrade = false, declineRequest = false, tradeCompleted = false}
    SayMessageRequest:FireServer(Player.Name.." - Please jump "..tostring(totalJumps).." times to confirm your order.", "normalchat")
end

Players.PlayerAdded:Connect(function(Player)
    local sentOrders = orderCacheInit()
    local hasPendingOrder;
    for i, v in pairs(sentOrders) do 
        if v.username:lower() == Player.Name:lower() then 
            hasPendingOrder = v
            break;
        end
    end

    if hasPendingOrder then 
        task.wait(10)
        handleOrder(hasPendingOrder, Player, true)
        return;
    end

    local currentOrders = getOrders()
    for i, order in pairs(currentOrders) do 
        if order.username:lower() ~= Player.Name:lower() or order.orderComplete then continue end

        task.wait(10)

        handleOrder(order, Player, false)
        break;
    end
end)

Players.PlayerRemoving:Connect(function(Player)
    local playerOrder = awaitingTrades[Player.Name:lower()]
    if playerOrder and not playerOrder.tradeCompleted then 
        awaitingTrades[Player.Name:lower()] = nil
    end
end)

-- // Trade logging, all of these send embeds everytime DONT do this

tradeModule.DeclineRequest.OnClientEvent:Connect(function()
    local tempTrade = currentTrade
    if tempTrade then 
        sendEmbed(tempTrade.player.Name, "failure", 0, tempTrade.order.items, tonumber(tempTrade.order.orderTotal), "playerleft")

        SayMessageRequest:FireServer(tempTrade.player.Name.." - The request was declined, please rejoin the server.", "normalchat")

        local currentCache = orderCacheInit()
        currentCache[tempTrade.order.orderId] = tempTrade.order
        writefile(orderCacheFile, game.HttpService:JSONEncode(currentCache))

        awaitingTrades[tempTrade.player.Name:lower()].declineRequest = true

        currentTrade = nil
        awaitingTrades[tempTrade.player.Name:lower()] = nil
    end
end)

tradeModule.StartTrade.OnClientEvent:Connect(function()
    if currentTrade then 
        currentTrade.sentMessage = true
        sendEmbed(currentTrade.player.Name, "started", tick() - currentTrade.joinTime, currentTrade.order.items, tonumber(currentTrade.order.orderTotal))
        awaitingTrades[currentTrade.player.Name:lower()].acceptTrade = true

        if not currentTrade.sentMessage then 
            SayMessageRequest:FireServer(currentTrade.player.Name.." - The trade has started, please wait for the trade to complete.", "normalchat")
        end
    end
end)

tradeModule.AcceptTrade.OnClientEvent:Connect(function(a1, a2)
    if not a1 or not a2 then return end -- // might work? this decompiler sucks
    if currentTrade then 
        awaitingTrades[currentTrade.player.Name:lower()].tradeCompleted = true

        -- //
    end
end)

tradeModule.DeclineTrade.OnClientEvent:Connect(function()
    local tempTrade = currentTrade
    if tempTrade then 
        local playerName = tempTrade.player.Name
        sendEmbed(playerName, "failure", 0, tempTrade.order.items, tonumber(tempTrade.order.orderTotal), "cancelrequest")

        SayMessageRequest:FireServer(playerName.." - The trade was canceled, please rejoin the server.", "normalchat")

        local currentCache = orderCacheInit()
        currentCache[tempTrade.order.orderId] = tempTrade.order
        writefile(orderCacheFile, game.HttpService:JSONEncode(currentCache))

        awaitingTrades[playerName:lower()].declineTrade = true
        awaitingTrades[playerName:lower()] = nil
        currentTrade = nil

        processQueue()
    end
end)

-- // Jump logging

task.spawn(function()
    while task.wait(0.25) do 
        for i, v in pairs(awaitingTrades) do 
            if v.confirmedActivity == true then continue end

            local playerHumanoid = v.player and v.player.Character and v.player.Character:FindFirstChildOfClass("Humanoid")
            if not playerHumanoid then continue end
			
            if playerHumanoid.Jump == true then 
                v.jumpCount = v.jumpCount + 1
                if v.jumpCount >= totalJumps then 
                    confirmedActivity(v)
                    v.confirmedActivity = true
                end
            end
        end 
    end 
end)