print("Executed newClient.lua")

local sendOrderSuccess = true -- // When the user completes the order
local sendOrderFailure = false -- // Could be for if the user cancels or doesn't accept the order
local sendOrderStarted = true -- // When the user accepts the trade

local tagHandler = ""
local secretKey = ""
local totalJumps = 3
local queueTimeout = 30; -- // Amount of seconds to wait before moving to the next order, if the order is not completed
local orderWebhook = ""
local orderCacheFile = "MM2_Cache.json"

local productIdLink = ""

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

-- // trading system

local tradeSystem = {} -- // all trades that are currently in queue, remove when being processed
local currentTrade; 

local function alertQueueStatus(currentUser) -- // send a message in roblox chat with the current ETA of the queue till the next order
    if not currentTrade then return end
    local currentQueuePosition = 0 
    local ETA = 0;
    for i, v in pairs(tradeSystem) do 
        currentQueuePosition = currentQueuePosition + 1
    end

    if currentQueuePosition > 0 then 
        local itemAmount = 0;
        for i2, v2 in pairs(currentTrade.order.items) do 
            if currentTrade.sentItems and currentTrade.sentItems[i2] then continue end
            itemAmount = itemAmount + v2
        end

        ETA = ETA + (itemAmount / 4) * averageTradeTime
    end

    local minutes = math.floor(ETA / 60)
    local seconds = math.floor(ETA - (minutes * 60))

    SayMessageRequest:FireServer(currentUser.Name.." - There are currently "..tostring(currentQueuePosition).." orders in queue, with an ETA of "..tostring(minutes).."m "..tostring(seconds).."s till the next order.", "normalchat")
end 

local function handleTrade(processItems, currentTrade)
    local playerObject = currentTrade.player
    if not currentTrade or not currentTrade.player then return false end 
    local sucess, response = pcall(tradeModule.SendRequest.InvokeServer, tradeModule.SendRequest, playerObject)
    if not sucess then 
        warn("Failed to send request to "..tostring(playerObject.Name), sucess, response)
        return false 
    end

    print("Sent request to "..tostring(playerObject.Name), sucess, response)

    local playerName = playerObject.Name
    local justSent = tick()
    repeat task.wait() until not currentTrade or tick() - justSent >= queueTimeout or currentTrade.acceptTrade or currentTrade.declineRequest 
    if not currentTrade or not currentTrade.acceptTrade then 
        if tick() - justSent >= queueTimeout then 
            sendEmbed(playerName, "failure", 0, currentTrade.order.items, tonumber(currentTrade.order.orderTotal), "timeout")
        end
        
        if currentTrade.declineRequest then 
            sendEmbed(playerName, "failure", 0, currentTrade.order.items, tonumber(currentTrade.order.orderTotal), "cancelrequest")
        end

        local success, response = pcall(cancelRequest.FireServer, cancelRequest, playerObject)
        if not success then 
            warn("Failed to cancel request for "..tostring(playerObject.Name), success, response)
        end
        
        return false 
    end

    for DataID, v in pairs(processItems) do  
        for i2 = 1, v do 
            print("Sending "..tostring(DataID).."(" .. tostring(v) .. ") to "..tostring(playerObject.Name))
            offerItem:FireServer(DataID, "Weapons")
        end
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
    until not currentTrade or tick() - justSent >= queueTimeout or currentTrade.tradeCompleted or currentTrade.declineTrade
    if not currentTrade or not currentTrade.tradeCompleted then 
        if tick() - justSent >= queueTimeout then 
            sendEmbed(playerName, "failure", 0, currentTrade.order.items, tonumber(currentTrade.order.orderTotal), "timeout")
        end
        
        if currentTrade.declineTrade then 
            sendEmbed(playerName, "failure", 0, currentTrade.order.items, tonumber(currentTrade.order.orderTotal), "cancelrequest")
        end

        local success, response = pcall(declineTrade.FireServer, declineTrade, playerObject)
        if not success then 
            warn("Failed to decline trade for "..tostring(playerObject.Name), success, response)
        end
        
        return false 
    end

    currentTrade.tradeCompleted = false
    currentTrade.acceptTrade = false

    return true
end

local function processQueue()
    local currentQueuePosition = 0
    for i, v in pairs(tradeSystem) do 
        currentQueuePosition = currentQueuePosition + 1
    end

    if currentQueuePosition == 0 then return end
    if currentQueuePosition > 1 then    
        -- // alert next in queue
        local nextInQueue = next(tradeSystem)
        if nextInQueue then 
            local nextTrade = tradeSystem[nextInQueue]
            if nextTrade then 
                alertQueueStatus(nextTrade.player)
            end
        end
    end     

    currentTrade = tradeSystem[next(tradeSystem)]
    if not currentTrade then return end

    local orderItems = currentTrade.order.items
    local itemTitles = {}
    for title in pairs(orderItems) do 
        table.insert(itemTitles, title)
    end

    local tradesNeeded = math.round(#itemTitles / 4 + 0.5)

    local batchSize = 4
    local batchStart = 1
    local totalItems = #itemTitles

    print("Starting trade for "..currentTrade.player.Name.." with "..tostring(tradesNeeded).." trades needed.")
    tradeSystem[currentTrade.userid] = nil

    local completedTrades = 0;
    local processedItems = {}
    while batchStart <= totalItems do 
        local nextItems = {}
        for i = batchStart, math.min(batchStart + batchSize - 1, totalItems) do 
            local itemTitle = itemTitles[i]
            nextItems[itemTitle] = orderItems[itemTitle]
            warn("Adding "..itemTitle.." to nextItems")
        end 

        if next(nextItems) then 
            local didTrade = handleTrade(nextItems, currentTrade)
            if not didTrade then break end

            task.wait(3)

            completedTrades = completedTrades + 1

            -- // remove the items from the order
            for i, v in pairs(nextItems) do 
                warn("ADDING "..i.." TO PROCESSED ITEMS")
                table.insert(processedItems, i)
            end
        end

        batchStart = batchStart + batchSize
    end 

    if completedTrades == tradesNeeded then 
        sendEmbed(currentTrade.player.Name, "success", tick() - currentTrade.joinTime, currentTrade.order.items, tonumber(currentTrade.order.orderTotal))

        SayMessageRequest:FireServer(currentTrade.player.Name.." - The trade has completed, thank you for your purchase!", "normalchat")
        
        -- // remove the order from the cache
        local currentCache = orderCacheInit()
        currentCache[currentTrade.order.orderId] = nil

        writefile(orderCacheFile, game.HttpService:JSONEncode(currentCache))
        markOrderComplete(currentTrade.order.orderId)
    else 
        warn("WRITING TO CACHE", #processedItems)
        print("--- START OF PROCESSED ITEMS ---")
        for i, v in pairs(processedItems) do 
            print(i, v)
        end

        print("--- END OF PROCESSED ITEMS ---")

        local currentCache = orderCacheInit()

        -- // combine old sent items with new sent items
        if currentCache[currentTrade.order.orderId] then 
            for i, v in pairs(currentCache[currentTrade.order.orderId].sentItems) do 
                table.insert(processedItems, v)
            end
        end
        
        currentTrade.order.sentItems = processedItems
        currentCache[currentTrade.order.orderId] = currentTrade.order
            
        writefile(orderCacheFile, game.HttpService:JSONEncode(currentCache))
    end 

    currentTrade = nil
    processQueue()
end

local function confirmedActivity(tradeData)
    local player = tradeData.player
    local order = tradeData.order

    local enoughItems = hasStock(order.items)
    if not enoughItems then 
        SayMessageRequest:FireServer(player.Name.." - We do not have enough stock to complete this order, please contact staff at our server.", "normalchat")
        sendEmbed(player.Name, "failure", 0, order.items, tonumber(order.orderTotal), "notenoughstock")
        return 
    end

    SayMessageRequest:FireServer(player.Name.." - Please wait while we process your order.", "normalchat")
    if not currentTrade then 
        processQueue()
    end
end

local function handleOrder(order, Player)
    if not order or not Player or tradeSystem[Player.UserId] then return end 

    tradeSystem[Player.UserId] = {
        sentMessage = false,
        userid = tonumber(order.userid),
        player = Player,
        order = order,
        jumpCount = 0,
        joinTime = tick(),
        confirmedActivity = false,
        sentTrade = tick(),
        acceptTrade = false,
        declineTrade = false,
        declineRequest = false,
        tradeCompleted = false
    }

    SayMessageRequest:FireServer(Player.Name.." - Please jump "..tostring(totalJumps).." times to confirm your order.", "normalchat")
end

Players.PlayerAdded:Connect(function(Player)
    local sentOrders = orderCacheInit()
    for i, v in pairs(sentOrders) do 
        print("Checking order for "..tostring(Player.UserId), v.userid)
        if tostring(v.userid) == tostring(Player.UserId) and not v.orderComplete then 
            print("Passed first check!")
            task.wait(10)

            -- // remove sentItems from the items table
            local currentItems = v.items
            local sentItems = v.sentItems
            warn("SENT ITEMS", sentItems)
            if sentItems then 
                for i2, v2 in pairs(sentItems) do 
                    v.items[v2] = nil;
                    warn("REMOVED "..v2.." FROM ITEMS TABLE")
                end
            end

            handleOrder(v, Player)
            return;
        end
    end

    local currentOrders = getOrders()
    for i, order in pairs(currentOrders) do 
        if tonumber(order.userid) ~= Player.UserId or order.orderComplete then continue end 

        task.wait(10)

        handleOrder(order, Player)
        break;
    end 
end)

Players.PlayerRemoving:Connect(function(Player)
    if tradeSystem[Player.UserId] then 
        tradeSystem[Player.UserId] = nil
    end
end)

-- // Trade logging

tradeModule.DeclineRequest.OnClientEvent:Connect(function()
    local tempTrade = currentTrade
    if tempTrade then 
        sendEmbed(tempTrade.player.Name, "failure", 0, tempTrade.order.items, tonumber(tempTrade.order.orderTotal), "playerleft")

        SayMessageRequest:FireServer(tempTrade.player.Name.." - The request was declined, please rejoin the server.", "normalchat")
        currentTrade.declineRequest = true
    end
end)

tradeModule.StartTrade.OnClientEvent:Connect(function()
    if currentTrade then 
        currentTrade.sentMessage = true
        currentTrade.acceptTrade = true
        sendEmbed(currentTrade.player.Name, "started", tick() - currentTrade.joinTime, currentTrade.order.items, tonumber(currentTrade.order.orderTotal))

        if not currentTrade.sentMessage then 
            SayMessageRequest:FireServer(currentTrade.player.Name.." - The trade has started, please wait for the trade to complete.", "normalchat")
        end
    end
end)

tradeModule.AcceptTrade.OnClientEvent:Connect(function(wasCompleted, tradeData)
    if not wasCompleted or not tradeData then return end
    if currentTrade then 
        currentTrade.tradeCompleted = true;
    end
end)

tradeModule.DeclineTrade.OnClientEvent:Connect(function()
    if currentTrade then 
        local playerName = currentTrade.player.Name
        sendEmbed(playerName, "failure", 0, currentTrade.order.items, tonumber(currentTrade.order.orderTotal), "cancelrequest")

        SayMessageRequest:FireServer(playerName.." - The trade was canceled, please rejoin the server.", "normalchat")
        currentTrade.declineTrade = true
    end
end)

-- // Jump logging

task.spawn(function()
    while task.wait(0.25) do 
        for i, v in pairs(tradeSystem) do 
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