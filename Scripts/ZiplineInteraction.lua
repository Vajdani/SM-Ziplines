dofile "$CONTENT_DATA/Scripts/util.lua"

---@class ZiplineInteraction : ToolClass
ZiplineInteraction = class()

function ZiplineInteraction:server_onCreate()
    g_ziplineInteraction = self.tool
end

function ZiplineInteraction:sv_setZiplineState(args)
    self.network:sendToClient(args.player, "cl_setZiplineState", args.state)
    self:sv_setZiplineData(args)
end

function ZiplineInteraction:sv_setZiplineData(args)
    self.network:sendToClient(args.player, "cl_setZiplineData", args.data)
end



function ZiplineInteraction:client_onCreate()
    self.poleTrigger = nil
    self.lockingPole = nil
end

function ZiplineInteraction:client_onUpdate()
    local char = sm.localPlayer.getPlayer().character
    local cPub = char.clientPublicData
    if cPub and cPub.isRidingZipline then
        if CanInteract() then
            sm.gui.setInteractionText(
                sm.gui.getKeyBinding("Jump", true).."Dismount\t",
                sm.gui.getKeyBinding("Use", true).."Reverse direction\t",
                ""
            )
        else
            sm.gui.setInteractionText(sm.gui.getKeyBinding("Jump", true), "Dismount\t", "")
        end

        if CanPlayerBoost(cPub.zipDir, cPub.isReverse, sm.localPlayer.getDirection()) then
            sm.gui.setInteractionText("", sm.gui.getKeyBinding("Forward", true), "Slide")
        end

        return
    end

    local lock = char:getLockingInteractable()
    if lock and lock ~= self.lockingPole then return end

    local start = sm.localPlayer.getRaycastStart()
    local hit, result = sm.physics.spherecast(start, start + sm.localPlayer.getDirection() * 5, 0.15, nil, 8)

    if hit then
        sm.gui.setInteractionText("", sm.gui.getKeyBinding("Use", true), "#{INTERACTION_USE}")
    end

    local pole = result:getAreaTrigger()
    if self.poleTrigger ~= pole then
        if pole then
            local lockingPole = pole:getUserData().pole.interactable
            char:setLockingInteractable(lockingPole)
            self.lockingPole = lockingPole
        else
            char:setLockingInteractable(nil)
        end

        self.poleTrigger = pole
    end
end

function ZiplineInteraction:cl_setZiplineState(state)
    local char = sm.localPlayer.getPlayer().character
    char.clientPublicData = char.clientPublicData or {}
    char.clientPublicData.isRidingZipline = state
end

function ZiplineInteraction:cl_setZiplineData(args)
    local char = sm.localPlayer.getPlayer().character
    if args == nil then
        char.clientPublicData.zipDir = nil
        char.clientPublicData.isReverse = nil
    else
        local zipDir = args.zipDir
        if zipDir ~= nil then
            char.clientPublicData.zipDir = zipDir
        end

        local isReverse = args.isReverse
        if isReverse ~= nil then
            char.clientPublicData.isReverse = isReverse
        end
    end
end