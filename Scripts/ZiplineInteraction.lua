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
    local isRidingZipline = cPub and cPub.isRidingZipline
    if isRidingZipline then
        local interText = sm.gui.getKeyBinding("Jump", true).."Dismount\t"
        if CanInteract() then
            interText = interText..sm.gui.getKeyBinding("Use", true).."Reverse direction\t"
        end

        if CanPlayerBoost(cPub.zipDir, cPub.isReverse, sm.localPlayer.getDirection()) and char.velocity:length2() > 1 then
            interText = interText..sm.gui.getKeyBinding("Forward", true).."Slide"
        end

        sm.gui.setInteractionText(interText, "")
        --return
    end

    local lock = char:getLockingInteractable()
    if lock and lock ~= self.lockingPole or isRidingZipline then return end

    local hit, pole = DoZiplineInteractionRaycast(isRidingZipline and self.poleTrigger)
    if hit then
        sm.gui.setInteractionText("", sm.gui.getKeyBinding("Use", true), "Attach to zipline")
    end

    if self.poleTrigger ~= pole then
        if pole then
            local lockingPole = pole:getUserData().pole.interactable
            char:setLockingInteractable(lockingPole)
            self.lockingPole = lockingPole
        else
            char:setLockingInteractable(nil)
            self.lockingPole = nil
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