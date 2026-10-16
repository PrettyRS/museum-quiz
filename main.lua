local Answers = require("answers")

local EVENT_ID = "museum_quiz_answer_outline"
local POLL_INTERVAL = 5
local PULSE_PERIOD = 1.2
local TEXT_PADDING = 3

local QUESTION_COMPONENT = "VM_NATURAL_HISTORY__VM_NATHIS_QUESTION"
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

local onLogic

local function onServerLogic()
    if not inMuseumMap() then
        return
    end

    Event.ServerLogic.Unsubscribe(EVENT_ID)
    Event.Logic.Subscribe(EVENT_ID, onLogic)
    updateOutline()
end

onLogic = function(event)
    if event.logicTick % POLL_INTERVAL ~= 0 then
        return
    end

    if not inMuseumMap() then
        if outline ~= nil then
            clearOutline(getLabel(QUESTION_COMPONENT) ~= nil)
        end
        activeInterface = nil
        Event.Logic.Unsubscribe(EVENT_ID)
        Event.ServerLogic.Subscribe(EVENT_ID, onServerLogic)
        return
    end

    updateOutline()
    if outline ~= nil then
        pulseTime = (pulseTime + POLL_INTERVAL / 50) % PULSE_PERIOD
        outline.alpha = 0.65 + 0.35 * math.sin(pulseTime * (2 * math.pi / PULSE_PERIOD))
    end
end

if inMuseumMap() then
    Event.Logic.Subscribe(EVENT_ID, onLogic)
    updateOutline()
else
    Event.ServerLogic.Subscribe(EVENT_ID, onServerLogic)
end

function PluginShutdown()
    Event.Logic.Unsubscribe(EVENT_ID)
    Event.ServerLogic.Unsubscribe(EVENT_ID)
    clearOutline(getLabel(QUESTION_COMPONENT) ~= nil)
end
