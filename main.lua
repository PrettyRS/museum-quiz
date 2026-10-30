local Answers = require("answers")

local EVENT_ID = "museum_quiz_answer_outline"
local READY_TICKS = 30
local POLL_INTERVAL = 5
local PULSE_PERIOD = 1.2
local TEXT_PADDING = 3

local QUESTION_COMPONENT = "VM_NATURAL_HISTORY__VM_NATHIS_QUESTION"
local HOST_COMPONENT = "TOPLEVEL_V2__MODAL_WINDOW_CONTENT"
local ANSWER_COMPONENTS = {
    "VM_NATURAL_HISTORY__VM_NATHIS_ANSWER_01",
    "VM_NATURAL_HISTORY__VM_NATHIS_ANSWER_02",
    "VM_NATURAL_HISTORY__VM_NATHIS_ANSWER_03",
}

local outlinedID = nil
local outline = nil
local pulseTime = 0
local activeInterface = nil
local textMetrics = nil
local readyTicksLeft = 0
local onLogic

local function getLabel(componentName)
    local componentID = id.Component[componentName]
    if componentID == nil then
        return nil
    end

    local component = ui.Interfaces:GetComponent(componentID)
    if component == nil or component.type ~= ui.ComponentType.LABEL then
        return nil
    end
    return component, componentID
end

local function inMuseumMap()
    if not Player.IsAvailable() then
        return false
    end

    local player = Player.GetEntity()
    if player == nil or not player.isValid then
        return false
    end

    local coord = player.coordGrid
    return coord.level == 0 and coord.mapSquareX == 27 and coord.mapSquareZ == 77
end

local function clearOutline(interfaceLoaded)
    if outline == nil then
        return
    end

    Event.Logic.Unsubscribe(EVENT_ID)
    if interfaceLoaded then
        outline:Destroy()
    end
    outline = nil
    outlinedID = nil
    textMetrics = nil
end

local function positionOutline(answer)
    local content, fontID = answer.content, answer.font
    local labelWidth, labelHeight = answer.width, answer.height
    local spacing, maxLines = answer.lineSpacing, answer.maxLines
    if textMetrics == nil or textMetrics.content ~= content or textMetrics.fontID ~= fontID
        or textMetrics.labelWidth ~= labelWidth or textMetrics.labelHeight ~= labelHeight
        or textMetrics.spacing ~= spacing or textMetrics.maxLines ~= maxLines
    then
        local font = config.Font.FromID(fontID)
        if font == nil or labelWidth <= 0 or labelHeight <= 0 then
            return false
        end

        local width = math.min(labelWidth, font:GetStringWidthMultiline(content, labelWidth))
        local baseHeight, lines = font:GetStringHeightAndLineCount(content, labelWidth, 0)
        if maxLines > 0 then
            lines = math.min(lines, maxLines)
        end
        -- Some client fonts do not expose a baseline; their one-line height is a close spacing.
        local lineSpacing = spacing ~= nil and spacing > 0 and spacing or font.baseline or baseHeight
        local height = math.min(labelHeight, baseHeight + (lines - 1) * lineSpacing)
        textMetrics = {
            content = content, fontID = fontID, labelWidth = labelWidth, labelHeight = labelHeight,
            spacing = spacing, maxLines = maxLines, width = width, height = height,
        }
    end

    local width, height = textMetrics.width, textMetrics.height
    local x, y = answer.x, answer.y
    if answer.alignHorizontal == ui.AlignMode.CENTRE then
        x = x + math.floor((labelWidth - width) / 2)
    elseif answer.alignHorizontal == ui.AlignMode.BOTTOMRIGHT then
        x = x + labelWidth - width
    end
    if answer.alignVertical == ui.AlignMode.CENTRE then
        y = y + math.floor((labelHeight - height) / 2)
    elseif answer.alignVertical == ui.AlignMode.BOTTOMRIGHT then
        y = y + labelHeight - height
    end

    x, y = x - TEXT_PADDING, y - TEXT_PADDING
    width, height = width + 2 * TEXT_PADDING, height + 2 * TEXT_PADDING
    if outline.x ~= x or outline.y ~= y then
        outline:SetPos(x, y)
    end
    if outline.width ~= width or outline.height ~= height then
        outline:SetSize(width, height)
    end
    return true
end

local function showOutline(answer, componentID)
    if outlinedID == componentID and outline ~= nil and outline.parent == answer.parent then
        if not positionOutline(answer) then
            clearOutline(true)
        end
        return
    end

    clearOutline(true)
    local parent = answer.parent
    if parent == nil then
        return
    end
    outline = ui.Rectangle.new(parent)
    outlinedID = componentID
    outline.fill = false
    outline.outlineThickness = 2
    outline.clickthrough = true
    outline.enabled = false
    outline.colour = Vector4.new(0, 0.97, 0.5, 1)
    if not positionOutline(answer) then
        clearOutline(true)
        return
    end
    outline:MoveToFront()
    Event.Logic.Subscribe(EVENT_ID, onLogic)
    pulseTime = 0
end

local function updateOutline()
    local question = getLabel(QUESTION_COMPONENT)
    if question == nil then
        clearOutline(false)
        activeInterface = nil
        return
    end

    if activeInterface ~= question.parentInterface then
        clearOutline(false)
        activeInterface = question.parentInterface
    end

    local correctAnswer = Answers[question.content]
    if correctAnswer == nil then
        clearOutline(true)
        return
    end

    for _, componentName in ipairs(ANSWER_COMPONENTS) do
        local answer, componentID = getLabel(componentName)
        if answer ~= nil and answer.content == correctAnswer then
            showOutline(answer, componentID)
            return
        end
    end

    clearOutline(true)
end

local subscribedHost = nil

local function attachHostHook()
    local hostID = id.Component[HOST_COMPONENT]
    local host = hostID ~= nil and ui.Interfaces:GetComponent(hostID) or nil
    if host == subscribedHost then
        return
    end

    -- Listeners on an unloaded host are removed with its interface.
    subscribedHost = host
    if host ~= nil then
        host:Subscribe(ui.Hook.ONSUBCHANGE, EVENT_ID, function()
            if inMuseumMap() then
                updateOutline()
                if outline == nil then
                    if readyTicksLeft == 0 then
                        Event.Logic.Subscribe(EVENT_ID, onLogic)
                    end
                    readyTicksLeft = READY_TICKS
                else
                    readyTicksLeft = 0
                end
            end
            return true
        end)
    end
end

local function onServerLogic()
    attachHostHook()
    if not inMuseumMap() then
        if readyTicksLeft > 0 then
            readyTicksLeft = 0
            Event.Logic.Unsubscribe(EVENT_ID)
        end
        if outline ~= nil then
            clearOutline(getLabel(QUESTION_COMPONENT) ~= nil)
        end
        activeInterface = nil
        return
    end

    updateOutline()
    if outline ~= nil then
        readyTicksLeft = 0
    end
end

onLogic = function(event)
    if readyTicksLeft > 0 then
        if not inMuseumMap() then
            onServerLogic()
            return
        end

        readyTicksLeft = readyTicksLeft - 1
        updateOutline()
        if outline == nil then
            if readyTicksLeft == 0 then
                Event.Logic.Unsubscribe(EVENT_ID)
            end
            return
        end
        readyTicksLeft = 0
    end

    if event.logicTick % POLL_INTERVAL ~= 0 then
        return
    end

    onServerLogic()
    if outline ~= nil then
        pulseTime = (pulseTime + POLL_INTERVAL / 50) % PULSE_PERIOD
        outline.alpha = 0.65 + 0.35 * math.sin(pulseTime * (2 * math.pi / PULSE_PERIOD))
    end
end

Event.ServerLogic.Subscribe(EVENT_ID, onServerLogic)
onServerLogic()

function PluginShutdown()
    local hostID = id.Component[HOST_COMPONENT]
    if hostID ~= nil and subscribedHost ~= nil
        and ui.Interfaces:GetComponent(hostID) == subscribedHost
    then
        subscribedHost:Unsubscribe(ui.Hook.ONSUBCHANGE, EVENT_ID)
    end
    Event.ServerLogic.Unsubscribe(EVENT_ID)
    if readyTicksLeft > 0 then
        Event.Logic.Unsubscribe(EVENT_ID)
    end
    clearOutline(getLabel(QUESTION_COMPONENT) ~= nil)
end
