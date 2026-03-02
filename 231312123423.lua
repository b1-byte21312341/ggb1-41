--убрать трейд хелпер
local WindUI = loadstring(game:HttpGet("https://raw.githubusercontent.com/Footagesus/WindUI/main/dist/main.lua"))()

local Window = WindUI:CreateWindow({
	Title = "Project Reverse [Adopt Me] - Cool Things!",
	Icon = "slice",
	Transparent = true,
	Author = "By Project Reverse [Egorikusa]",
    Size = UDim2.fromOffset(580, 460),
    MinSize = Vector2.new(429, 280),
    MaxSize = Vector2.new(1000, 800),
    Theme = "Dark",
    SideBarWidth = 180,
})

Window:EditOpenButton({
    Title = "Open Prev UI",
    Icon = "monitor",
    CornerRadius = UDim.new(0,32),
    StrokeThickness = 2,
    Color = ColorSequence.new( -- gradient
        Color3.fromHex("FF0F7B"), 
        Color3.fromHex("F89B29")
    ),
    OnlyMobile = false,
    Enabled = true,
    Draggable = true,
})


local spawnersAndCratesSection = Window:Section({
    Title = 'Spawner',
    Icon = 'egg',
    Opened = false,
})

local tradehelperSection = Window:Section({
    Title = 'Trade Helper',
    Icon = 'handshake',
    Opened = false,
})

local inventoryhelperSection = Window:Section({
    Title = 'Inventory Helper',
    Icon = 'backpack',
    Opened = false,
})


-- Spawner Sector
local SpawnerSector = spawnersAndCratesSection:Tab({
    Title = 'Pet Spawner',
    Locked = false,
})

-- Trading Sectors

local TradeHelperSector = tradehelperSection:Tab({
    Title = 'Trade Info',
    Locked = false,
})




-- Inventory Sectors

local InventoryHelper = inventoryhelperSection:Tab({
    Title = 'Inventory Analyzer',
    Locked = false,
})

local function LOAD_ADOPT_THINGS()
local module = {}

local load = require(game.ReplicatedStorage:WaitForChild("Fsys")).load
set_thread_identity(2)
local clientData = load("ClientData")
local items = load("KindDB")
local router = load("RouterClient")
local downloader = load("DownloadClient")
local animationManager = load("AnimationManager")
local petRigs = load("new:PetRigs")

local _origPredict = clientData.predict
local _origGet = clientData.get
local _origGetData = clientData.get_data
local _origRollback = clientData.rollback_prediction
local _origRegisterCallback = clientData.register_callback
local _origUpdate = clientData.update

pcall(function()
    if islclosure and islclosure(_origPredict) then
        for i = 1, 50 do
            local name, value = debug.getupvalue(_origPredict, i)
            if name == nil then break end
            if type(value) == "table" and rawget(value, "predict") then
                _origPredict = value.predict or _origPredict
                _origGet = value.get or _origGet
                _origGetData = value.get_data or _origGetData
                _origRollback = value.rollback_prediction or _origRollback
                _origUpdate = value.update or _origUpdate
                break
            end
        end
    end
end)

set_thread_identity(8)

local petModels = {}
local pets = {}
local equippedPet = nil
local mountedPet = nil
local currentMountTrack = nil

local localTradeItems = {}
local tradeOfferOrder = {}
local isInjectingTrade = false
local fakeTradeHistory = {}
local lastTradeState = nil
local LocalPlayer = game.Players.LocalPlayer
local oldGet

local function deepCloneTrade(t)
    if type(t) ~= "table" then return t end
    local tt = typeof and typeof(t)
    if tt == "Instance" or tt == "Color3" or tt == "CFrame" or tt == "Vector3" or tt == "EnumItem" then return t end
    local copy = {}
    for k, v in pairs(t) do copy[k] = deepCloneTrade(v) end
    return copy
end

local function getMyOfferKey(state)
    if not state then return nil end
    if tostring(state.sender) == LocalPlayer.Name then
        return "sender_offer"
    elseif tostring(state.recipient) == LocalPlayer.Name then
        return "recipient_offer"
    end
    return nil
end

local function hasLocalItems(offerItems)
    local localCount = 0
    for _ in pairs(localTradeItems) do localCount = localCount + 1 end
    if localCount == 0 then return false end
    if #offerItems ~= localCount then return false end
    for _, item in ipairs(offerItems) do
        if not localTradeItems[item.unique] then return false end
    end
    return true
end

local function injectFakeItems(state)
    if not state or next(localTradeItems) == nil then return state end
    local key = getMyOfferKey(state)
    if not key or not state[key] then return state end
    local existingItems = state[key].items or {}
    if hasLocalItems(existingItems) then return state end

    local modified = deepCloneTrade(state)
    local newItems = {}

    for _, uid in ipairs(tradeOfferOrder) do
        if localTradeItems[uid] then
            table.insert(newItems, localTradeItems[uid])
        end
    end

    modified[key].items = newItems
    return modified
end

local function updateData(key, action)
    local data = _origGet(key)
    if data == nil then return end

    local ok, clonedData = pcall(table.clone, data)
    if not ok then return end
    local result = action(clonedData)
    if result ~= nil then
        pcall(_origPredict, key, result)
        pcall(function()
            local store = _origGetData()
            local existing = store and store[LocalPlayer.Name] and store[LocalPlayer.Name][key]
            if existing and type(existing) == "table" and type(result) == "table" then
                for k, v in pairs(result) do
                    existing[k] = v
                end
            end
        end)
    end
end

local function getUniqueId()
    local HttpService = game:GetService("HttpService")
    return HttpService:GenerateGUID(false)
end

local function getPetModel(kind)
    if petModels[kind] then
        return petModels[kind]
    end

    local streamed = downloader.promise_download_copy("Pets", kind):expect()
    petModels[kind] = streamed
    return streamed
end

local function createPet(id, properties)
    local uniqueId = getUniqueId()
    local pet = nil
    set_thread_identity(2)
    updateData("inventory", function(inventory)
        local newPets = table.clone(inventory.pets)
        local item = items[id]
        pet = {
            unique = uniqueId,
            category = "pets",
            id = id,
            kind = item.kind,
            newness_order = 0,
            properties = properties
        }

        newPets[uniqueId] = pet
        inventory.pets = newPets

        return inventory
    end)
    set_thread_identity(8)
    pets[uniqueId] = {
        data = pet,
        model = nil
    }
    return pet
end

local function neonify(model, entry)
    local petModel = model:FindFirstChild("PetModel")
    if not petModel then
        return
    end
    for neonPart, configuration in pairs(entry.neon_parts) do
        local trueNeonPart = petRigs.get(petModel).get_geo_part(petModel, neonPart)
        trueNeonPart.Material = configuration.Material
        trueNeonPart.Color = configuration.Color
    end
end

local function addPetWrapper(wrapper)
    updateData("pet_char_wrappers", function(petWrappers)
        wrapper.unique = #petWrappers + 1
        wrapper.index = #petWrappers + 1
        petWrappers[#petWrappers + 1] = wrapper
        return petWrappers
    end)
end

local function addPetState(state)
    updateData("pet_state_managers", function(petStates)
        petStates[#petStates + 1] = state
        return petStates
    end)
end

local function findIndex(array, finder)
    for index, value in pairs(array) do
        local isIt = finder(value, index)
        if isIt then
            return index
        end
    end
    return nil
end

local function removePetWrapper(uniqueId)
    updateData("pet_char_wrappers", function(petWrappers)
        local index = findIndex(petWrappers, function(wrapper)
            return wrapper.pet_unique == uniqueId
        end)
        if not index then
            return petWrappers
        end
        table.remove(petWrappers, index)
        for wrapperIndex, wrapper in pairs(petWrappers) do
            wrapper.unique = wrapperIndex
            wrapper.index = wrapperIndex
        end
        return petWrappers
    end)
end

local function clearPetState(uniqueId)
    local pet = pets[uniqueId]
    if not pet then
        return
    end

    if not pet.model then
        return
    end

    updateData("pet_state_managers", function(states)
        local index = findIndex(states, function(state)
            return state.char == pet.model
        end)

        if not index then
            return states
        end

        local clonedStates = table.clone(states)

        clonedStates[index] = table.clone(clonedStates[index])
        clonedStates[index].states = {}

        return clonedStates
    end)
end


local function setPetState(uniqueId, id)
    local pet = pets[uniqueId]

    if not pet then
        return
    end

    if not pet.model then
        return
    end

    updateData("pet_state_managers", function(states)
        local index = findIndex(states, function(state)
            return state.char == pet.model
        end)

        if not index then
            return states
        end

        local clonedStates = table.clone(states)

        clonedStates[index] = table.clone(clonedStates[index])
        clonedStates[index].states = {
            { id = id }
        }

        return clonedStates
    end)
end

local function attachPlayerToPet(pet)
    local character = game.Players.LocalPlayer.Character

    if not character then
        return false
    end

    if not character.PrimaryPart then
        return false
    end

    local ridePosition = pet:FindFirstChild("RidePosition", true)

    if not ridePosition then
        return false
    end

    local sourceAttachment = Instance.new("Attachment")

    sourceAttachment.Parent = ridePosition
    sourceAttachment.Position = Vector3.new(0, 1.237, 0)
    sourceAttachment.Name = "SourceAttachment"

    local stateConnection = Instance.new("RigidConstraint")

    stateConnection.Name = "StateConnection"
    stateConnection.Attachment0 = sourceAttachment
    stateConnection.Attachment1 = character.PrimaryPart.RootAttachment

    stateConnection.Parent = character

    return true
end


local function clearPlayerState()
    updateData("state_manager", function(state)
        local clonedState = table.clone(state)
        clonedState.states = {}
        clonedState.is_sitting = false
        return clonedState
    end)
end


local function setPlayerState(id)
    updateData("state_manager", function(state)
        local clonedState = table.clone(state)

        clonedState.states = {
            { id = id }
        }

        clonedState.is_sitting = true

        return clonedState
    end)
end


local function removePetState(uniqueId)
    local pet = pets[uniqueId]

    if not pet then
        return
    end

    if not pet.model then
        return
    end

    updateData("pet_state_managers", function(petStates)
        local index = findIndex(petStates, function(state)
            return state.char == pet.model
        end)

        if not index then
            return petStates
        end

        table.remove(petStates, index)
        return petStates
    end)
end

local function unmount(uniqueId)
    local pet = pets[uniqueId]

    if not pet then
        return
    end

    if not pet.model then
        return
    end

    if currentMountTrack then
        currentMountTrack:Stop()
        currentMountTrack:Destroy()
    end

    local sourceAttachment = pet.model:FindFirstChild("SourceAttachment", true)

    if sourceAttachment then
        sourceAttachment:Destroy()
    end

    if game.Players.LocalPlayer.Character then
        for _, descendant in pairs(game.Players.LocalPlayer.Character:GetDescendants()) do
            if descendant:IsA("BasePart") and descendant:GetAttribute("HaveMass") then
                descendant.Massless = false
            end
        end
    end

    clearPetState(uniqueId)
    clearPlayerState()

    pet.model:ScaleTo(1)

    mountedPet = nil
end

local function mount(uniqueId, playerState, petState)
    local pet = pets[uniqueId]

    if not pet then
        return
    end

    if not pet.model then
        return
    end

    local player = game.Players.LocalPlayer

    if not player.Character then
        return
    end

    if not player.Character.PrimaryPart then
        return
    end

    mountedPet = uniqueId

    setPetState(uniqueId, petState)
    setPlayerState(playerState)

    pet.model:ScaleTo(2)
    attachPlayerToPet(pet.model)

    currentMountTrack = player.Character.Humanoid.Animator:LoadAnimation(animationManager.get_track("PlayerRidingPet"))
    player.Character.Humanoid.Sit = true

    for _, descendant in pairs(player.Character:GetDescendants()) do
        if descendant:IsA("BasePart") and descendant.Massless == false then
            descendant.Massless = true
            descendant:SetAttribute("HaveMass", true)
        end
    end

    currentMountTrack:Play()
end

local function fly(uniqueId)
    mount(uniqueId, "PlayerFlyingPet", "PetBeingFlown")
end

local function ride(uniqueId)
    mount(uniqueId, "PlayerRidingPet", "PetBeingRidden")
end

local function unequip(item)
    local pet = pets[item.unique]

    if not pet then
        return
    end

    if not pet.model then
        return
    end

    unmount(item.unique)

    removePetWrapper(item.unique)
    removePetState(item.unique)

    pet.model:Destroy()
    pet.model = nil

    equippedPet = nil

    pcall(function()
        updateData("equip_manager", function(em)
            local catItems = table.clone(em[item.category] or {})
            for i = #catItems, 1, -1 do
                if catItems[i].unique == item.unique then
                    table.remove(catItems, i)
                end
            end
            em[item.category] = catItems
            return em
        end)
    end)
end

local function equip(item)
    if equippedPet then
        unequip(equippedPet)
    end

    if oldGet then
        local wrappers = _origGet("pet_char_wrappers")
        if wrappers then
            for _, w in pairs(wrappers) do
                if w.player == game.Players.LocalPlayer and not pets[w.pet_unique] then
                    oldGet("ToolAPI/Unequip"):InvokeServer(w.pet_unique)
                end
            end
        end
    end

    local petModel = getPetModel(item.kind):Clone()

    local char = game.Players.LocalPlayer.Character
    if char and char.PrimaryPart then
        petModel:PivotTo(char.PrimaryPart.CFrame * CFrame.new(3, 0, 0))
    end

    petModel.Parent = workspace
    pets[item.unique].model = petModel

    if item.properties.neon or item.properties.mega_neon then
        pcall(neonify, petModel, items[item.kind])
    end

    equippedPet = item

    addPetWrapper({
        char = petModel,
        mega_neon = item.properties.mega_neon,
        neon = item.properties.neon,
        player = game.Players.LocalPlayer,
        entity_controller = game.Players.LocalPlayer,
        controller = game.Players.LocalPlayer,
        rp_name = item.properties.rp_name or "",
        pet_trick_level = item.properties.pet_trick_level,
        pet_unique = item.unique,
        pet_id = item.id,
        location = {
            full_destination_id = "housing",
            destination_id = "housing",
            house_owner = game.Players.LocalPlayer
        },
        pet_progression = {
            friendship_level = item.properties.friendship_level,
            age = item.properties.age,
            percentage = 0
        },
        are_colors_sealed = false,
        is_pet = true
    })

    addPetState({
        char = petModel,
        player = game.Players.LocalPlayer,
        store_key = "pet_state_managers",
        is_sitting = false,
        chars_connected_to_me = {},
        states = {}
    })

    pcall(function()
        updateData("equip_manager", function(em)
            local catItems = table.clone(em[item.category] or {})
            for i = #catItems, 1, -1 do
                if catItems[i].unique == item.unique then
                    table.remove(catItems, i)
                end
            end
            table.insert(catItems, 1, item)
            em[item.category] = catItems
            return em
        end)
    end)
end

oldGet = router.get

local function createRemoteFunctionMock(callback)
    return {
        InvokeServer = function(_, ...)
            return callback(...)
        end
    }
end

local function createRemoteEventMock(callback)
    return {
        FireServer = function(_, ...)
            return callback(...)
        end
    }
end

local equipRemote = createRemoteFunctionMock(function(uniqueId, metadata)
    local pet = pets[uniqueId]

    if not pet then
        if equippedPet then
            unequip(equippedPet)
        end
        return oldGet("ToolAPI/Equip"):InvokeServer(uniqueId, metadata)
    end

    equip(pet.data)

    return true, {
        action = "equip",
        is_server = true
    }
end)

local unequipRemote = createRemoteFunctionMock(function(uniqueId)
    local pet = pets[uniqueId]

    if not pet then
        return oldGet("ToolAPI/Unequip"):InvokeServer(uniqueId)
    end

    unequip(pet.data)

    return true, {
        action = "unequip",
        is_server = true
    }
end)

local rideRemote = createRemoteFunctionMock(function(item)
    ride(item.pet_unique)
end)

local flyRemote = createRemoteFunctionMock(function(item)
    fly(item.pet_unique)
end)

local unmountRemoteFunction = createRemoteFunctionMock(function()
    unmount(mountedPet)
end)

local unmountRemoteEvent = createRemoteEventMock(function()
    unmount(mountedPet)
end)

local getTradeHistoryRemote = createRemoteFunctionMock(function()
    local realHistory = {}
    pcall(function()
        realHistory = oldGet("TradeAPI/GetTradeHistory"):InvokeServer() or {}
    end)
    if #fakeTradeHistory == 0 then return realHistory end
    local merged = {}
    for _, real in ipairs(realHistory) do
        local dominated = false
        for _, fake in ipairs(fakeTradeHistory) do
            local sameUsers = (real.sender_user_id == fake.sender_user_id and real.recipient_user_id == fake.recipient_user_id)
                or (real.sender_user_id == fake.recipient_user_id and real.recipient_user_id == fake.sender_user_id)
            if sameUsers and math.abs(real.timestamp - fake.timestamp) < 30 then
                dominated = true
                break
            end
        end
        if not dominated then
            table.insert(merged, real)
        end
    end
    for _, record in ipairs(fakeTradeHistory) do
        table.insert(merged, record)
    end
    table.sort(merged, function(a, b)
        return a.timestamp < b.timestamp
    end)
    return merged
end)

local addItemToOfferRemote = createRemoteEventMock(function(uniqueId)
    if pets[uniqueId] then
        localTradeItems[uniqueId] = pets[uniqueId].data
    else
        local inv = _origGet("inventory")
        if inv then
            for _, catItems in pairs(inv) do
                if type(catItems) == "table" and catItems[uniqueId] then
                    localTradeItems[uniqueId] = catItems[uniqueId]
                    break
                end
            end
        end
    end
    table.insert(tradeOfferOrder, uniqueId)
end)

local removeItemFromOfferRemote = createRemoteEventMock(function(uniqueId)
    localTradeItems[uniqueId] = nil
    for i, id in ipairs(tradeOfferOrder) do
        if id == uniqueId then
            table.remove(tradeOfferOrder, i)
            break
        end
    end
    task.defer(function()
        isInjectingTrade = true
        pcall(function()
            set_thread_identity(2)
            _origRollback("trade")
            set_thread_identity(8)
        end)
        if next(localTradeItems) == nil then
            isInjectingTrade = false
            return
        end
        local current = _origGet("trade")
        if not current then
            isInjectingTrade = false
            return
        end
        local modified = injectFakeItems(current)
        if modified and modified ~= current then
            pcall(function()
                set_thread_identity(2)
                _origPredict("trade", modified)
                set_thread_identity(8)
            end)
        end
        isInjectingTrade = false
    end)
end)

router.get = function(name)
    if name == "ToolAPI/Equip" then
        return equipRemote
    end

    if name == "ToolAPI/Unequip" then
        return unequipRemote
    end

    if name == "AdoptAPI/RidePet" then
        return rideRemote
    end

    if name == "AdoptAPI/FlyPet" then
        return flyRemote
    end

    if name == "AdoptAPI/ExitSeatStatesYield" then
        return unmountRemoteFunction
    end

    if name == "AdoptAPI/ExitSeatStates" then
        return unmountRemoteEvent
    end

    if name == "TradeAPI/AddItemToOffer" then
        if checkcaller() then return oldGet(name) end
        return addItemToOfferRemote
    end

    if name == "TradeAPI/RemoveItemFromOffer" then
        if checkcaller() then return oldGet(name) end
        return removeItemFromOfferRemote
    end

    if name == "TradeAPI/GetTradeHistory" then
        return getTradeHistoryRemote
    end

    return oldGet(name)
end

pcall(function()
    local tradeGui = LocalPlayer.PlayerGui:FindFirstChild("TradeApp")
    if tradeGui then
        tradeGui:GetPropertyChangedSignal("Enabled"):Connect(function()
            if not tradeGui.Enabled then
                tradeGui.Enabled = true
            end
        end)
        tradeGui.Enabled = true
    end
end)

set_thread_identity(2)
_origRegisterCallback("trade", function(_, tradeState, _)
    if isInjectingTrade then return end
    if tradeState == nil then
        pcall(function()
            if lastTradeState and next(localTradeItems) ~= nil then
                local sOffer = lastTradeState.sender_offer
                local rOffer = lastTradeState.recipient_offer
                local isCompleted = (sOffer and rOffer) and (
                    (sOffer.confirmed and rOffer.confirmed) or
                    (lastTradeState.current_stage == "confirmation")
                )
                if isCompleted then
                    local senderIsLocal = tostring(lastTradeState.sender) == LocalPlayer.Name
                    local senderItems = sOffer.items or {}
                    local recipientItems = rOffer.items or {}
                    local trimmedSender = {}
                    for _, item in ipairs(senderItems) do
                        table.insert(trimmedSender, {
                            category = item.category,
                            kind = item.kind,
                            id = item.id,
                            properties = {
                                flyable = item.properties and item.properties.flyable or nil,
                                rideable = item.properties and item.properties.rideable or nil,
                                neon = item.properties and item.properties.neon or nil,
                                mega_neon = item.properties and item.properties.mega_neon or nil,
                                age = item.properties and item.properties.age or nil,
                            }
                        })
                    end
                    local trimmedRecipient = {}
                    for _, item in ipairs(recipientItems) do
                        table.insert(trimmedRecipient, {
                            category = item.category,
                            kind = item.kind,
                            id = item.id,
                            properties = {
                                flyable = item.properties and item.properties.flyable or nil,
                                rideable = item.properties and item.properties.rideable or nil,
                                neon = item.properties and item.properties.neon or nil,
                                mega_neon = item.properties and item.properties.mega_neon or nil,
                                age = item.properties and item.properties.age or nil,
                            }
                        })
                    end
                    local senderPlayer = lastTradeState.sender
                    local recipientPlayer = lastTradeState.recipient
                    local record = {
                        trade_id = "fake_" .. tostring(tick()) .. "_" .. math.random(10000, 99999),
                        sender_items = trimmedSender,
                        recipient_items = trimmedRecipient,
                        sender_name = sOffer.player_name or (typeof(senderPlayer) == "Instance" and senderPlayer.Name or ""),
                        recipient_name = rOffer.player_name or (typeof(recipientPlayer) == "Instance" and recipientPlayer.Name or ""),
                        sender_user_id = typeof(senderPlayer) == "Instance" and senderPlayer.UserId or 0,
                        recipient_user_id = typeof(recipientPlayer) == "Instance" and recipientPlayer.UserId or 0,
                        timestamp = os.time(),
                    }
                    table.insert(fakeTradeHistory, 1, record)
                end
            end
        end)
        lastTradeState = nil
        localTradeItems = {}
        tradeOfferOrder = {}
        pcall(function()
            _origRollback("trade")
        end)
        return
    end
    lastTradeState = deepCloneTrade(tradeState)
    if next(localTradeItems) ~= nil then
        local injected = injectFakeItems(lastTradeState)
        if injected then lastTradeState = injected end
    end
    if next(localTradeItems) == nil then return end
    local key = getMyOfferKey(tradeState)
    if not key or not tradeState[key] then return end
    if hasLocalItems(tradeState[key].items or {}) then return end
    task.defer(function()
        if next(localTradeItems) == nil then return end
        local current = _origGet("trade")
        if not current then return end
        local modified = injectFakeItems(current)
        if modified ~= current then
            isInjectingTrade = true
            local ok, err = pcall(function()
                set_thread_identity(2)
                _origPredict("trade", modified)
                set_thread_identity(8)
            end)
            isInjectingTrade = false
        end
    end)
end)

_origRegisterCallback("inventory", function(_, newInventory, _)
    if not newInventory then return end
    local hasFakePets = false
    for _ in pairs(pets) do hasFakePets = true break end
    if not hasFakePets then return end

    local allFakesPresent = true
    if newInventory.pets then
        for uniqueId, _ in pairs(pets) do
            if not newInventory.pets[uniqueId] then
                allFakesPresent = false
                break
            end
        end
    else
        allFakesPresent = false
    end
    if allFakesPresent then return end

    local realData = _origGetData()
    local realInv = realData and realData[LocalPlayer.Name] and realData[LocalPlayer.Name].inventory
    if not realInv then return end

    local merged = table.clone(realInv)
    merged.pets = table.clone(merged.pets or {})
    for uniqueId, petEntry in pairs(pets) do
        if not merged.pets[uniqueId] then
            merged.pets[uniqueId] = petEntry.data
        end
    end
    task.defer(function()
        pcall(function()
            set_thread_identity(2)
            _origPredict("inventory", merged)
            set_thread_identity(8)
        end)
    end)
end)
set_thread_identity(8)

pcall(function()
    set_thread_identity(2)
    local OfferPaneClass = load("OfferPane")
    set_thread_identity(8)
    if OfferPaneClass and OfferPaneClass._build_slot then
        local origBuildSlot = OfferPaneClass._build_slot
        OfferPaneClass._build_slot = function(self, ...)
            local saved = self.props and self.props.do_not_display_tags
            if self.props then
                self.props.do_not_display_tags = false
            end
            local result = origBuildSlot(self, ...)
            if self.props then
                self.props.do_not_display_tags = saved
            end
            return result
        end
    end
end)

for _, charWrapper in pairs(_origGet("pet_char_wrappers") or {}) do
    oldGet("ToolAPI/Unequip"):InvokeServer(charWrapper.pet_unique)
end

local Loads = require(game.ReplicatedStorage.Fsys).load
local InventoryDB = Loads("InventoryDB")

function GetPetByName(name)
    for i,v in pairs(InventoryDB.pets) do
        if v.name:lower() == name:lower() then
            return v.id
        end
    end
    return false
end

module.SpawnPet = createPet
module.FindPet = GetPetByName

return module
end

local ImportedFunctions = LOAD_ADOPT_THINGS()

    local chosenNeonLevel = 'Normal'

    local chosenPet = 'Shadow Dragon'

    set_thread_identity(6)

    SpawnerSector:Dropdown({
        Title = "Select Pet Neon Type (FR/NFR/MFR)",
        Values = {'Normal', 'Neon', 'Mega Neon'},
        Value = chosenNeonLevel,
        Callback = function(option)
            chosenNeonLevel = option or 'Normal'
        end
    })

    SpawnerSector:Input({
        Title = "Select Pet Name",
        Value = chosenPet,
        Callback = function(value)
            chosenPet = value or 'Cat'
        end
    })

    SpawnerSector:Button({
        Title = "Spawn Pet",
        Callback = function()
            local pet = ImportedFunctions.FindPet(chosenPet)
            if pet then
                if chosenNeonLevel == 'Normal' then
                    ImportedFunctions.SpawnPet(pet, {
                        pet_trick_level = 0,
                        rideable = true,
                        flyable = true,
                        friendship_level = 0,
                        age = 1,
                        rp_name = ""
                    })
                elseif chosenNeonLevel == 'Neon' then
                    ImportedFunctions.SpawnPet(pet, {
                        pet_trick_level = 0,
                        neon = true,
                        rideable = true,
                        flyable = true,
                        friendship_level = 0,
                        age = 1,
                        rp_name = ""
                    })
                elseif chosenNeonLevel == 'Mega Neon' then
                    ImportedFunctions.SpawnPet(pet, {
                        pet_trick_level = 0,
                        mega_neon = true,
                        rideable = true,
                        flyable = true,
                        friendship_level = 0,
                        age = 1,
                        rp_name = ""
                    })
                end
            end
        end
    })



local function GetAdoptValues()
    local HttpService = game:GetService("HttpService")
    local url = "http://72.56.90.233:3910/api/valuables/get-game-valuables?game=ame"
    local folder, file = "ValueData", "ValueData/adopt_values.json"
    local cacheLifetime = 3600

    if not isfolder(folder) then makefolder(folder) end

	if isfile(file) then
		local ok, raw = pcall(readfile, file)
		if ok and raw ~= "" then
			local success, data = pcall(HttpService.JSONDecode, HttpService, raw)
			if success and data and tick() - data._time < cacheLifetime then
				return data.data
			end
		end
	end

	local success, res = pcall(game.HttpGet, game, url)
	if not success then
		local ok, cached = pcall(function()
			return HttpService:JSONDecode(readfile(file))
		end)
		return ok and cached and cached.data or {}
	end

	local decoded = HttpService:JSONDecode(res)
	writefile(file, HttpService:JSONEncode({ data = decoded.data, _time = tick() }))
	return decoded.data
end

local function GetBetterAdoptValues()
    local values = {}
    local parsed = GetAdoptValues()

    for i, v in pairs(parsed) do
        values[v.name] = v.price
    end

    return values
end

local function GetInventoryParser(guy)
    local allItems = {}

    local Loads = require(game.ReplicatedStorage.Fsys).load
    local ClientData = Loads("ClientData")
    local InventoryDB = Loads("InventoryDB")
    local Inventory = _origGet("inventory") or ClientData.get("inventory")
    if not Inventory then return allItems end

    for class, stuff in pairs(Inventory) do
        if type(stuff) ~= "table" then continue end
        local classDB = InventoryDB[class]
        if not classDB then continue end
        for id, v in pairs(stuff) do
            local data = classDB[v.id]
            if data and v.properties then
                local name = data.name
                local props = v.properties
                
                name = (props.mega_neon and "Mega Neon " or props.neon and "Neon " or "")
                    ..(props.flyable and "Fly " or "")
                    ..(props.rideable and "Ride " or "")
                    ..name

                allItems[name] = (allItems[name] or 0) + 1
            end
        end
    end
    
    return allItems
end

local function getInventoryDataAsMessage()
    local items = GetInventoryParser()
    local marketData = GetBetterAdoptValues()

    local itemList = {}
    local totalValue = 0
    local totalCount = 0

    for name, count in pairs(items) do
        local price = marketData[name] or 0
        local value = price * count
   
        if value > 0 then
            table.insert(itemList, {
                name = name,
                count = count,
                price = price,
                total = value,
            })
            totalValue = totalValue + value
            totalCount = totalCount + count
        end
    end

    table.sort(itemList, function(a, b)
        return a.total > b.total
    end)

    local lines = {
        "Inventory Analysis:",
        string.rep("-", 40)
    }

    for _, item in ipairs(itemList) do
        table.insert(lines, string.format(
            "%-20s x%-4d | $%8.2f | $%10.2f",
            item.name,
            item.count,
            item.price,
            item.total
        ))
    end

    table.insert(lines, string.rep("-", 40))
    table.insert(lines, string.format("Total Items: %d", totalCount))
    table.insert(lines, string.format("Total Value: $%d", math.floor(totalValue)))

    return table.concat(lines, "\n")
end

local function AnalyzeInventory(section)
    info = section:Paragraph({
        Title = 'Please Wait!',
        Desc = 'Collecting information about you!',
        Buttons = {
            {
                Icon = "bird",
                Title = "Copy Inventory Information",
                Callback = function()
                    res, inventoryData = pcall(getInventoryDataAsMessage)
                    setclipboard(inventoryData)
                end,
            }
        }
    })

    res, inventoryData = pcall(getInventoryDataAsMessage)
 
    pcall(function()
        set_thread_identity(7)
        info:SetTitle('Your Inventory Data:')
    end)

    info:SetDesc(inventoryData)
    print(2)
    isAnalyzing = false
end

InventoryHelper:Paragraph({
    Title = 'What is this?',
    Desc = 'This page will help u know ur inventory value, all information about ur inventory will be sorted and organized here!',
    Color = 'White',
})

InventoryHelper:Button({
    Title = "Start Analyzis",
    Desc = "This button will analyze ur inventory and give u all data about it!",
    Locked = false,
    Callback = function()
        if not isAnalyzing then
            isAnalyzing = true
            AnalyzeInventory(InventoryHelper)
        end
    end
})


















DISPLAY_VALUES = false

tradegui = game:GetService("Players").LocalPlayer.PlayerGui.TradeApp
local Loads = require(game.ReplicatedStorage.Fsys).load
local RouterClient = Loads("RouterClient")
local DataChanged = RouterClient.get('DataAPI/DataChanged')
local InventoryDB = Loads("InventoryDB")
local send_trade = RouterClient.get("TradeAPI/SendTradeRequest")

function tradeallfunc()
    for i,v in pairs(game.Players:GetPlayers()) do
        send_trade:FireServer(v)
    end
end

valuelabels = Instance.new('TextLabel')
valuelabels.Parent = tradegui
valuelabels.Position = UDim2.new(0.54, 1, 0.2, 0.45)
valuelabels.Size = UDim2.new(0.1, 0.1, 0.1, 0.1)
valuelabels.TextSize = 20

undervalues = Instance.new('TextLabel')
undervalues.Parent = valuelabels
undervalues.Position = UDim2.new(0.5, 0.1, 0.1, 0.1)
undervalues.Text = 'Total Value:'
undervalues.TextSize = 14
undervalues.TextStrokeTransparency = 0.8


valuelabels2 = Instance.new('TextLabel')
valuelabels2.Parent = tradegui
valuelabels2.Position = UDim2.new(0.36, 1, 0.2, 0.45)
valuelabels2.Size = UDim2.new(0.1, 0.1, 0.1, 0.1)
valuelabels2.TextSize = 20

undervalues2 = Instance.new('TextLabel')
undervalues2.Parent = valuelabels2
undervalues2.Position = UDim2.new(0.5, 0.1, 0.1, 0.1)
undervalues2.Text = 'Total Value:'
undervalues2.TextSize = 14
undervalues2.TextStrokeTransparency = 0.8

valuelabels.Visible = false
valuelabels2.Visible = false

tradegui.Frame:GetPropertyChangedSignal('Visible'):Connect(function(...)
    state = DISPLAY_VALUES and tradegui.Frame.Visible
    valuelabels.Visible = state
    valuelabels2.Visible = state
end)

local Values = GetBetterAdoptValues()

DataChanged.OnClientEvent:Connect(function(...)
    x = {...}
    if type(x[3]) == "table" and x[2] == "trade" then
        trade = x[3]
        if trade.recipient == game.Players.LocalPlayer.Name then
            me = 'recipient_offer'
        elseif trade.sender == game.Players.LocalPlayer.Name then
            me = 'sender_offer'
        end
        if tostring(trade.recipient) == game.Players.LocalPlayer.Name then
            me = 'recipient_offer'
            notme = 'sender_offer'
        end
        if tostring(trade.sender) == game.Players.LocalPlayer.Name then
            me = 'sender_offer'
            notme = 'recipient_offer'
        end
        me = trade[me]
        notme = trade[notme]
        my_value = 0
        his_value = 0
        for i,v in pairs(me.items) do
            local ItemName = InventoryDB[v.category][v.id].name
            local props = v.properties

            local fullName = (props.mega_neon and "Mega Neon " or props.neon and "Neon " or "")
                    ..(props.flyable and "Fly " or "")
                    ..(props.rideable and "Ride " or "")
                    ..ItemName

            my_value += (Values[fullName] or 0)
        end

        for i,v in pairs(notme.items) do
            local ItemName = InventoryDB[v.category][v.id].name
            local props = v.properties

            local fullName = (props.mega_neon and "Mega Neon " or props.neon and "Neon " or "")
                    ..(props.flyable and "Fly " or "")
                    ..(props.rideable and "Ride " or "")
                    ..ItemName

            his_value += (Values[fullName] or 0)
        end
        if my_value and his_value then
            valuelabels.Text = tostring(his_value) .. ' $'
            valuelabels2.Text = tostring(my_value) .. ' $'
        end
    end
end)

set_thread_identity(7)
TradeHelperSector:Toggle({
    Title = "Display Values In Trade",
    Desc = "Helps u decide is trade good or bad!",
    Type = "Checkbox",
    Default = false,
    Callback = function(state) 
        DISPLAY_VALUES = state
        if tradegui.Frame.Visible then
            valuelabels.Visible = state
            valuelabels2.Visible = state
        end
    end
})

TradeHelperSector:Button({
    Title = "Trade Everyone",
    Desc = "This button will send trade request to every single person on the server!",
    Locked = false,
    Callback = tradeallfunc,
})












