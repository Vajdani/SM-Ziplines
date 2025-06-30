---@class ZiplineSlider : ShapeClass
ZiplineSlider = class()
ZiplineSlider.connectionInput = sm.interactable.connectionType.logic
ZiplineSlider.connectionOutput = sm.interactable.connectionType.none
ZiplineSlider.maxParentCount = -1
ZiplineSlider.maxChildCount = 0

local attachRange = 5

function ZiplineSlider:server_onCreate()
    self.targetPole = self.storage:load()
    if self.targetPole then
        sm.event.sendToInteractable(self.targetPole.interactable, "sv_attachSlider", self.shape)
    end

    self.trigger = sm.areaTrigger.createAttachedBox(self.interactable, sm.vec3.one() * attachRange, sm.vec3.zero(), sm.quat.identity(), sm.areaTrigger.filter.areatrigger)
end

function ZiplineSlider:server_onFixedUpdate()
    local active, moveDir = self:getInputs()
    if active ~= self.interactable.active then
        if active then
            if self.targetPole then
                sm.event.sendToInteractable(self.targetPole.interactable, "sv_attachSlider", self.shape)
                self.targetPole = nil
            else
                self.targetPole = self:findPole()
                if self.targetPole then
                    sm.event.sendToInteractable(self.targetPole.interactable, "sv_attachSlider", self.shape)
                end
            end

            self.storage:save(self.targetPole)
        end

        self.interactable.active = active
    end

    if moveDir ~= self.interactable.power then
        self.interactable.power = moveDir
    end
end

function ZiplineSlider:sv_setTarget(target)
    self.targetPole = target
end



local col_active = {
    df7f00ff = true,
    df7f01ff = true
}
local col_fwd = {
    eeeeeeff = true,
}
local col_bwd = {
    ["222222ff"] = true
}
function ZiplineSlider:getInputs()
    local active, moveDir = false, 0
    for k, v in pairs(self.interactable:getParents()) do
        if not v.active then
            goto continue
        end

        local col = v.shape.color:getHexStr()
        if col_active[col] == true then
            active = true
        elseif col_fwd[col] == true then
            moveDir = moveDir + 1
        elseif col_bwd[col] == true then
            moveDir = moveDir - 1
        end

        ::continue::
    end

    return active, moveDir
end

function ZiplineSlider:findPole()
    local pole, minDistance = nil, math.huge
    local selfPos = self.shape.worldPosition
    for k, v in pairs(self.shape.shapesInSphere(selfPos, attachRange)) do
        if v.uuid == ZIPLINEPOLE  then
            local poleParent = (v.interactable.publicData or {}).poleParent
            if not poleParent then
                goto continue
            end

            local distance = (selfPos - v.worldPosition):length2()
            if distance < minDistance then
                pole, minDistance = poleParent, distance
            end
        end

        ::continue::
    end

    for k, v in ipairs(self.trigger:getContents()) do
        if type(v) == "AreaTrigger" then
            local userdata = v:getUserData()
            if not userdata or not userdata.pole then
                goto continue
            end

            local distance = (selfPos - v:getWorldPosition()):length2()
            if distance < minDistance then
                pole, minDistance = userdata.pole, distance
            end

            ::continue::
        end
    end

    return pole
end