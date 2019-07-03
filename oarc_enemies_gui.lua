-- oarc_enemis_gui.lua
-- July 2019
-- GUI for my enemy mod

require("mod-gui")

function OarcEnemiesGui(event)
    local player = game.players[event.player_index]
    if mod_gui.get_button_flow(player).oarc_enemies == nil then
        mod_gui.get_button_flow(player).add{name="oarc_enemies", type="button", caption="OE", style=mod_gui.button_style}
    end   
end

local function ExpandOarcEnemiesGui(player)
    local frame = mod_gui.get_frame_flow(player)["oe-panel"]
    if (frame) then
        frame.destroy()
    else
        local frame = mod_gui.get_frame_flow(player).add{type="frame", name="oe-panel", caption="Oarc's Enemies:", direction = "vertical"}
        
        frame.add{type="button", caption="Player Attack", name="oe_attack_player"}
        frame.add{type="button", caption="Science Labs Attack", name="oe_attack_labs"}

        local oe_info="General Info:" .. "\n" ..
                        "Groups: " .. #global.oarc_enemies.groups .. "\n" ..
                        "Units: " .. #global.oarc_enemies.units .. "\n" ..
                        "Attacks: " .. #global.oarc_enemies.attacks .. "\n" ..
                        "Labs: " .. #global.oarc_enemies.science_labs[player.name] .. "\n" ..
                        "Tech levels: " .. global.oarc_enemies.tech_levels[player.force.name] .. "\n" ..
                        "Timer: " .. global.oarc_enemies.player_timers[player.name]
        AddLabel(frame, "oe_info", oe_info, my_longer_label_style)

    end
end

function OarcEnemiesGuiClick(event) 
    if not (event and event.element and event.element.valid) then return end
    local player = game.players[event.element.player_index]
    local name = event.element.name

    if (name == "oarc_enemies") then
        ExpandOarcEnemiesGui(player)        
    end

    if (name == "oe_attack_player") then
        OarcEnemiesPlayerAttack(player.name)
    end

    if (name == "oe_attack_labs") then
        OarcEnemiesScienceLabAttack(player.force.name)
    end
    
end
