-- Load AceComm-3.0 if it's not already loaded
local AceComm = LibStub("AceComm-3.0")
local LD = LibStub("LibDeflate")
local AceSerializer = LibStub("AceSerializer-3.0")

local lastSession = 0
local lastItemLink = nil
local channel = "PARTY"
local RCLootCouncil_RollAlerts = LibStub("AceAddon-3.0"):NewAddon("RCLootCouncil RollAlerts", "AceComm-3.0")

local function decompressor(data)
    local decoded = LD:DecodeForWoWAddonChannel(data)
    if not decoded then return data end -- Assume it's a pre 0.10 message.
    local serializedMsg = LD:DecompressDeflate(decoded)
    return serializedMsg or ""
end

local function reversedSort(a, b)
    -- Compare roll numbers in descending order
    return a.roll > b.roll
end

local function output(message)
    SendChatMessage(message, channel)
end

local function setChatChannel()
    if IsInRaid() and (UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")) then
        channel = "RAID_WARNING"
    elseif IsInRaid() then
        channel = "RAID"
    else
        channel = "PARTY"
    end
end

local function OnRRollsReceived(session, ...)
    -- do nothing if you're not ML
    if not IsMasterLooter() then
        return
    end

    setChatChannel()

    local lootTable = RCLootCouncil:GetModule("RCVotingFrame").GetLootTable()

    -- trying to detect if the sesion contains a duplicate item, we get multiple events so it gets spammy
    if lootTable[session].link == lastItemLink and lastSession ~= session then
        return
    end

    lastSession = session
    lastItemLink = lootTable[session].link

    local candidates = {}
    for name, x in pairs(lootTable[session].candidates) do
        tinsert(candidates, { name = name, response = x["response"], roll = tonumber(x["roll"]) })
    end

    -- Find the highest priority response value, the lowest int value (e.g. 1 = bis, 2 = ms)
    local lowestResponse = math.huge  -- Start with a very large number
    for _, candidate in ipairs(candidates) do
        local responseNum = tonumber(candidate.response)
        if responseNum and responseNum < lowestResponse then
            lowestResponse = candidate.response
        end
    end

    -- we didn't find a response, print and return
    if lowestResponse == math.huge then
        output("No valid responses for " .. lootTable[session].link)
        return
    end

    -- Filter candidates to include only those with the lowest response value
    local filteredCandidates = {}
    for _, candidate in ipairs(candidates) do
        if candidate.response == lowestResponse then
            tinsert(filteredCandidates, candidate)
        end
    end

    -- Sort candidates by roll number in descending order
    table.sort(filteredCandidates, reversedSort)
    
    local responseText = RCLootCouncil:GetResponse(nil, lowestResponse)["text"]
    output("Top " .. responseText .. " rolls for: " .. lootTable[session].link)

    -- Print out only the top 3 candidates
    local numToIterate = math.min(3, #filteredCandidates)
    for i = 1, numToIterate do
        local candidate = filteredCandidates[i]
        output(string.format("%s rolled %s", candidate.name, candidate.roll))
    end
end

local function onCommReceived(prefix, message, distribution, sender)
    -- Check if the message is from RCLootCouncil
    if prefix ~= "RCLootCouncil" then return end

    local uncompressed = decompressor(message)
    local test, command, data = AceSerializer:Deserialize(uncompressed)

    if command ~= "rrolls" then return end

    -- wait for the UI to update first as we'll be pulling from the UI frame data
    C_Timer.After(0.1, function()
        OnRRollsReceived(unpack(data))
    end)
end

function RCLootCouncil_RollAlerts:OnInitialize()
    AceComm:RegisterComm("RCLootCouncil", onCommReceived)
end