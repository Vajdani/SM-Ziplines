dofile "$CONTENT_DATA/Scripts/util.lua"

if not g_gravityStrength then
    g_gravityStrength = 10
end

---@class ZiplineInteraction : ToolClass
ZiplineInteraction = class()

function ZiplineInteraction:server_onCreate()
    if g_ziplineInteraction then
        self.server_onFixedUpdate = function() end
        return
    end

    g_ziplineInteraction = self.tool
end

function ZiplineInteraction:server_onFixedUpdate()
    local gravity = sm.physics.getGravity()
    if g_gravityStrength ~= gravity then
        g_gravityStrength = gravity
        self.network:setClientData(g_gravityStrength)
    end
end

function ZiplineInteraction:sv_setZiplineState(args)
    self.network:sendToClient(args.player, "cl_setZiplineState", args)
end

function ZiplineInteraction:sv_setZiplineData(args)
    self.network:sendToClient(args.player, "cl_setZiplineData", args.data)
end



function ZiplineInteraction:client_onCreate()
    if g_cl_ziplineInteraction then
        self.client_onUpdate = function() end
        return
    end

    g_cl_ziplineInteraction = self.tool

    self.poleTrigger = nil
    self.lockingPole = nil
end

function ZiplineInteraction:client_onUpdate()
    local char = lplayer_get().character
    if not sm.exists(char) or char:isTumbling() then return end

    local cPub = char.clientPublicData
    local isRidingZipline = cPub and cPub.isRidingZipline
    if isRidingZipline then
        local interText = ico_jump.."Dismount\t"
        if CanInteract() then
            interText = interText..ico_use.."Reverse direction\t"
        end

        if CanPlayerBoost(cPub.zipDir, cPub.isReverse, lplayer_getDirection()) and char.velocity:length2() > 1 then
            interText = interText..ico_fwd.."Slide"
        end

        gui_setInteractionText(interText, "")
        --return
    end

    local lock = char:getLockingInteractable()
    if lock and lock:hasSeat() then return end

    local pole = DoZiplineInteractionRaycast(isRidingZipline and self.poleTrigger or nil)
    if pole then
        gui_setInteractionText("", ico_use, "Attach to zipline")
    end

    if isRidingZipline then return end

    if self.poleTrigger ~= pole then
        if pole ~= nil and sm.exists(pole) then
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

function ZiplineInteraction:client_onClientDataUpdate(data, channel)
    g_gravityStrength = data
end

function ZiplineInteraction:cl_setZiplineState(args)
    local char = lplayer_get().character
    char.clientPublicData = char.clientPublicData or {}
    char.clientPublicData.isRidingZipline = args.state

    self:cl_setZiplineData(args.data)
end

function ZiplineInteraction:cl_setZiplineData(args)
    local char = lplayer_get().character
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