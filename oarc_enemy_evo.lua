-- oarc_enemy_evo.lua
-- Converted into LUA from here: https://hastebin.com/udakacavap.js
-- Source is the Factorio Wiki

local biter_chance_list = {}
local spitter_chance_list = {}

-- values are in the form [evolution, weight]
local biter_weight_table = {
    {"small-biter",    {{0.0, 0.3}, {0.6, 0.0}}},
    {"medium-biter",   {{0.2, 0.0}, {0.6, 0.3}, {0.7, 0.1}}},
    {"big-biter",      {{0.5, 0.0}, {1.0, 0.4}}},
    {"behemoth-biter", {{0.9, 0.0}, {1.0, 0.3}}}
}

local spitter_weight_table = {
    {"small-biter",      {{0.0, 0.3}, {0.35, 0.0}}},
    {"small-spitter",    {{0.25, 0.0}, {0.5, 0.3}, {0.7, 0.0}}},
    {"medium-spitter",   {{0.4, 0.0}, {0.7, 0.3}, {0.9, 0.1}}},
    {"big-spitter",      {{0.5, 0.0}, {1.0, 0.4}}},
    {"behemoth-spitter", {{0.9, 0.0}, {1.0, 0.3}}}
}

-- calculates the interpolated value
local function lerp(low, high, pos)
    local s = high[1] - low[1]
    local l = (pos - low[1]) / s
    return ((low[2] * (1-l)) + (high[2] * l))
end

-- gets the weight list
local function getValues(map, evo)
    local result = {}
    local sum = 0

    for k,v in pairs(map) do
        local list = v[2];
        local low = list[1];
        local high = list[#list-1];

        for k2,v2 in pairs(list) do
            if ((v2[1] <= evo) and (v2[1] >  low[1])) then
                low = v2
            end
            if ((v2[1] >= evo) and (v2[1] < high[1])) then
                high = v2
            end
        end

        local val = nil;
        if (evo <= low[1]) then
            val = low[2]

        elseif (evo >= high[1]) then
            val = high[2]

        else
            val = lerp(low, high, evo)
        end
        sum = sum + val;
        table.insert(result, {v[1], val})
    end

    local total = 0
    for _,v in pairs(result) do
        v[2] = v[2] / sum
        total = total + v[2]
        v[2] = math.ceil(total*100)
        v[2] = math.min(v[2], 100)
        v[2] = math.max(0, v[2])
    end

    return result
end

-- Calculate the weight lists for a given evo and return the table.
function CalculateEvoChanceListBiters(evo)
    return getValues(biter_weight_table, evo)
end
function CalculateEvoChanceListSpitters(evo)
    return getValues(spitter_weight_table, evo)
end

-- Roll the dice on an enemy given the chance list created.
function GetEnemyFromChanceList(chance_list)

    if ((chance_list == nil) or (#chance_list == 0)) then
        SendBroadcastMsg("ERROR - need a valid chance list!")
        log("ERROR - need a valid chance list!")
        return "small-biter"
    end

    local rand = math.random(0, 100)
    for _,v in pairs(chance_list) do
        if (rand < v[2]) then
            return v[1]
        end
    end

    return "small-biter"
end
