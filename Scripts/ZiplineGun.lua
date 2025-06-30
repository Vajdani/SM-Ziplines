dofile( "$GAME_DATA/Scripts/game/AnimationUtil.lua" )
dofile( "$SURVIVAL_DATA/Scripts/util.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_shapes.lua" )
dofile( "$SURVIVAL_DATA/Scripts/game/survival_projectiles.lua" )

---@class ZiplineGun : ToolClass
ZiplineGun = class()

local Damage = 28

local renderables = {
	"$GAME_DATA/Character/Char_Tools/Char_spudgun/Base/char_spudgun_base_basic.rend",
	"$GAME_DATA/Character/Char_Tools/Char_spudgun/Barrel/Barrel_basic/char_spudgun_barrel_basic.rend",
	"$GAME_DATA/Character/Char_Tools/Char_spudgun/Sight/Sight_basic/char_spudgun_sight_basic.rend",
	"$GAME_DATA/Character/Char_Tools/Char_spudgun/Stock/Stock_broom/char_spudgun_stock_broom.rend",
	"$GAME_DATA/Character/Char_Tools/Char_spudgun/Tank/Tank_basic/char_spudgun_tank_basic.rend"
}
local renderablesTp = {
    "$GAME_DATA/Character/Char_Male/Animations/char_male_tp_spudgun.rend",
    "$GAME_DATA/Character/Char_Tools/Char_spudgun/char_spudgun_tp_animlist.rend"
}
local renderablesFp = {
    "$GAME_DATA/Character/Char_Tools/Char_spudgun/char_spudgun_fp_animlist.rend"
}

sm.tool.preloadRenderables( renderables )
sm.tool.preloadRenderables( renderablesTp )
sm.tool.preloadRenderables( renderablesFp )

function ZiplineGun:client_onCreate()
	self.shootEffect = sm.effect.createEffect( "SpudgunBasic - BasicMuzzel" )
	self.shootEffectFP = sm.effect.createEffect( "SpudgunBasic - FPBasicMuzzel" )

    self.isLocal = self.tool:isLocal()
end

function ZiplineGun:loadAnimations()
	self.tpAnimations = createTpAnimations(
		self.tool,
		{
			shoot = { "spudgun_shoot", { crouch = "spudgun_crouch_shoot" } },
			aim = { "spudgun_aim", { crouch = "spudgun_crouch_aim" } },
			aimShoot = { "spudgun_aim_shoot", { crouch = "spudgun_crouch_aim_shoot" } },
			idle = { "spudgun_idle" },
			pickup = { "spudgun_pickup", { nextAnimation = "idle" } },
			putdown = { "spudgun_putdown" }
		}
	)

	local movementAnimations = {
		idle = "spudgun_idle",
		idleRelaxed = "spudgun_relax",

		sprint = "spudgun_sprint",
		runFwd = "spudgun_run_fwd",
		runBwd = "spudgun_run_bwd",

		jump = "spudgun_jump",
		jumpUp = "spudgun_jump_up",
		jumpDown = "spudgun_jump_down",

		land = "spudgun_jump_land",
		landFwd = "spudgun_jump_land_fwd",
		landBwd = "spudgun_jump_land_bwd",

		crouchIdle = "spudgun_crouch_idle",
		crouchFwd = "spudgun_crouch_fwd",
		crouchBwd = "spudgun_crouch_bwd"
	}
	for name, animation in pairs( movementAnimations ) do
		self.tool:setMovementAnimation( name, animation )
	end

	setTpAnimation( self.tpAnimations, "idle", 5.0 )

	if self.isLocal then
		self.fpAnimations = createFpAnimations(
			self.tool,
			{
				equip = { "spudgun_pickup", { nextAnimation = "idle" } },
				unequip = { "spudgun_putdown" },

				idle = { "spudgun_idle", { looping = true } },
				shoot = { "spudgun_shoot", { nextAnimation = "idle" } },

				aimInto = { "spudgun_aim_into", { nextAnimation = "aimIdle" } },
				aimExit = { "spudgun_aim_exit", { nextAnimation = "idle", blendNext = 0 } },
				aimIdle = { "spudgun_aim_idle", { looping = true} },
				aimShoot = { "spudgun_aim_shoot", { nextAnimation = "aimIdle"} },

				sprintInto = { "spudgun_sprint_into", { nextAnimation = "sprintIdle",  blendNext = 0.2 } },
				sprintExit = { "spudgun_sprint_exit", { nextAnimation = "idle",  blendNext = 0 } },
				sprintIdle = { "spudgun_sprint_idle", { looping = true } },
			}
		)
	end

	self.normalFireMode = {
		fireCooldown = 0.20,
		spreadCooldown = 0.18,
		spreadIncrement = 2.6,
		spreadMinAngle = .25,
		spreadMaxAngle = 8,
		fireVelocity = 130.0,

		minDispersionStanding = 0.1,
		minDispersionCrouching = 0.04,

		maxMovementDispersion = 0.4,
		jumpDispersionMultiplier = 2
	}

	self.aimFireMode = {
		fireCooldown = 0.20,
		spreadCooldown = 0.18,
		spreadIncrement = 1.3,
		spreadMinAngle = 0,
		spreadMaxAngle = 8,
		fireVelocity =  130.0,

		minDispersionStanding = 0.01,
		minDispersionCrouching = 0.01,

		maxMovementDispersion = 0.4,
		jumpDispersionMultiplier = 2
	}

	self.fireCooldownTimer = 0.0
	self.spreadCooldownTimer = 0.0

	self.movementDispersion = 0.0

	self.sprintCooldownTimer = 0.0
	self.sprintCooldown = 0.3

	self.aimBlendSpeed = 3.0
	self.blendTime = 0.2

	self.jointWeight = 0.0
	self.spineWeight = 0.0
	local cameraWeight, cameraFPWeight = self.tool:getCameraWeights()
	self.aimWeight = math.max( cameraWeight, cameraFPWeight )

end

local isSprintAnim = {
    sprintInto = true,
    sprintIdle = true
}

local isAimAnim = {
    aimInto  = true,
    aimIdle  = true,
    aimShoot = true
}

function ZiplineGun:client_onUpdate( dt )
	local isSprinting =  self.tool:isSprinting()
	local isCrouching =  self.tool:isCrouching()

	if self.isLocal then
		if self.equipped then
            local currentAnim = self.fpAnimations.currentAnimation

            local isSprintAnimActive = isSprintAnim[currentAnim] == true
			if isSprinting and not isSprintAnimActive then
				swapFpAnimation( self.fpAnimations, "sprintExit", "sprintInto", 0.0 )
			elseif not isSprinting and isSprintAnimActive then
				swapFpAnimation( self.fpAnimations, "sprintInto", "sprintExit", 0.0 )
			end

            local isAimAnimActive = isAimAnim[currentAnim] == true
			if self.aiming and not isAimAnimActive then
				swapFpAnimation( self.fpAnimations, "aimExit", "aimInto", 0.0 )
            elseif not self.aiming and isAimAnimActive then
				swapFpAnimation( self.fpAnimations, "aimInto", "aimExit", 0.0 )
			end
		end
		updateFpAnimations( self.fpAnimations, self.equipped, dt )
	end

	if not self.equipped then
		if self.wantEquipped then
			self.wantEquipped = false
			self.equipped = true
		end
		return
	end

	if self.isLocal then
        local dir = sm.localPlayer.getDirection()
	    local effectPos
		if not self.aiming then
			effectPos = self.tool:getFpBonePos( "pejnt_barrel" ) + dir * 0.2
		else
			effectPos = self.tool:getFpBonePos( "pejnt_barrel" ) + dir * 0.45
		end

		self.shootEffectFP:setPosition( effectPos )
		self.shootEffectFP:setVelocity( self.tool:getMovementVelocity() )
		self.shootEffectFP:setRotation( sm.vec3.getRotation( vec3_up, dir ) )
	end

	local dir = self.tool:getTpBoneDir( "pejnt_barrel" )
	self.shootEffect:setPosition( self.tool:getTpBonePos( "pejnt_barrel" ) + dir * 0.2 )
	self.shootEffect:setVelocity( self.tool:getMovementVelocity() )
	self.shootEffect:setRotation( sm.vec3.getRotation( vec3_up, dir ) )

	self.fireCooldownTimer = math.max( self.fireCooldownTimer - dt, 0.0 )
	self.spreadCooldownTimer = math.max( self.spreadCooldownTimer - dt, 0.0 )
	self.sprintCooldownTimer = math.max( self.sprintCooldownTimer - dt, 0.0 )

	if self.isLocal then
		local dispersion = 0.0
		local fireMode = self.aiming and self.aimFireMode or self.normalFireMode
		local recoilDispersion = 1.0 - ( math.max( fireMode.minDispersionCrouching, fireMode.minDispersionStanding ) + fireMode.maxMovementDispersion )

		if isCrouching then
			dispersion = fireMode.minDispersionCrouching
		else
			dispersion = fireMode.minDispersionStanding
		end

		if self.tool:getRelativeMoveDirection():length() > 0 then
			dispersion = dispersion + fireMode.maxMovementDispersion * self.tool:getMovementSpeedFraction()
		end

		if not self.tool:isOnGround() then
			dispersion = dispersion * fireMode.jumpDispersionMultiplier
		end

		self.movementDispersion = dispersion

		self.spreadCooldownTimer = clamp( self.spreadCooldownTimer, 0.0, fireMode.spreadCooldown )
		local spreadFactor = fireMode.spreadCooldown > 0.0 and clamp( self.spreadCooldownTimer / fireMode.spreadCooldown, 0.0, 1.0 ) or 0.0

		self.tool:setDispersionFraction( clamp( self.movementDispersion + spreadFactor * recoilDispersion, 0.0, 1.0 ) )

		if self.aiming then
			if self.tool:isInFirstPersonView() then
				self.tool:setCrossHairAlpha( 0.0 )
			else
				self.tool:setCrossHairAlpha( 1.0 )
			end
			self.tool:setInteractionTextSuppressed( true )
		else
			self.tool:setCrossHairAlpha( 1.0 )
			self.tool:setInteractionTextSuppressed( false )
		end
	end

	local blockSprint = self.aiming or self.sprintCooldownTimer > 0.0
	self.tool:setBlockSprint( blockSprint )

	local playerDir = self.tool:getSmoothDirection()
	local angle = math.asin( playerDir:dot( vec3_up ) ) / ( math.pi / 2 )

	local crouchWeight = isCrouching and 1.0 or 0.0
	local normalWeight = 1.0 - crouchWeight

	local totalWeight = 0.0
	for name, animation in pairs( self.tpAnimations.animations ) do
		animation.time = animation.time + dt

		if name == self.tpAnimations.currentAnimation then
			animation.weight = math.min( animation.weight + ( self.tpAnimations.blendSpeed * dt ), 1.0 )

			if animation.time >= animation.info.duration - self.blendTime then
				if ( name == "shoot" or name == "aimShoot" ) then
					setTpAnimation( self.tpAnimations, self.aiming and "aim" or "idle", 10.0 )
				elseif name == "pickup" then
					setTpAnimation( self.tpAnimations, self.aiming and "aim" or "idle", 0.001 )
				elseif animation.nextAnimation ~= "" then
					setTpAnimation( self.tpAnimations, animation.nextAnimation, 0.001 )
				end
			end
		else
			animation.weight = math.max( animation.weight - ( self.tpAnimations.blendSpeed * dt ), 0.0 )
		end

		totalWeight = totalWeight + animation.weight
	end

	totalWeight = totalWeight == 0 and 1.0 or totalWeight
	for name, animation in pairs( self.tpAnimations.animations ) do
		local weight = animation.weight / totalWeight
		if name == "idle" then
			self.tool:updateMovementAnimation( animation.time, weight )
		elseif animation.crouch then
			self.tool:updateAnimation( animation.info.name, animation.time, weight * normalWeight )
			self.tool:updateAnimation( animation.crouch.name, animation.time, weight * crouchWeight )
		else
			self.tool:updateAnimation( animation.info.name, animation.time, weight )
		end
	end

	-- Third Person joint lock
	local relativeMoveDirection = self.tool:getRelativeMoveDirection()
	if ( ( ( isAnyOf( self.tpAnimations.currentAnimation, { "aimInto", "aim", "shoot" } ) and ( relativeMoveDirection:length() > 0 or isCrouching) ) or ( self.aiming and ( relativeMoveDirection:length() > 0 or isCrouching) ) ) and not isSprinting ) then
		self.jointWeight = math.min( self.jointWeight + ( 10.0 * dt ), 1.0 )
	else
		self.jointWeight = math.max( self.jointWeight - ( 6.0 * dt ), 0.0 )
	end

	if ( not isSprinting ) then
		self.spineWeight = math.min( self.spineWeight + ( 10.0 * dt ), 1.0 )
	else
		self.spineWeight = math.max( self.spineWeight - ( 10.0 * dt ), 0.0 )
	end

	local finalAngle = ( 0.5 + angle * 0.5 )
	self.tool:updateAnimation( "spudgun_spine_bend", finalAngle, self.spineWeight )

    local totalOffsetZ = lerp( -22.0, -26.0, crouchWeight )
	local totalOffsetY = lerp( 6.0, 12.0, crouchWeight )
	local crouchTotalOffsetX = clamp( ( angle * 60.0 ) -15.0, -60.0, 40.0 )
	local normalTotalOffsetX = clamp( ( angle * 50.0 ), -45.0, 50.0 )
	local totalOffsetX = lerp( normalTotalOffsetX, crouchTotalOffsetX , crouchWeight )
	local finalJointWeight = ( self.jointWeight )
	self.tool:updateJoint( "jnt_hips", vec3_new( totalOffsetX, totalOffsetY, totalOffsetZ ), 0.35 * finalJointWeight * ( normalWeight ) )

	local crouchSpineWeight = ( 0.35 / 3 ) * crouchWeight
	self.tool:updateJoint( "jnt_spine1", vec3_new( totalOffsetX, totalOffsetY, totalOffsetZ ), ( 0.10 + crouchSpineWeight )  * finalJointWeight )
	self.tool:updateJoint( "jnt_spine2", vec3_new( totalOffsetX, totalOffsetY, totalOffsetZ ), ( 0.10 + crouchSpineWeight ) * finalJointWeight )
	self.tool:updateJoint( "jnt_spine3", vec3_new( totalOffsetX, totalOffsetY, totalOffsetZ ), ( 0.45 + crouchSpineWeight ) * finalJointWeight )
	self.tool:updateJoint( "jnt_head", vec3_new( totalOffsetX, totalOffsetY, totalOffsetZ ), 0.3 * finalJointWeight )

	local bobbing = 1
    local blend = 1 - math.pow( 1 - 1 / self.aimBlendSpeed, dt * 60 )
	if self.aiming then
		self.aimWeight = sm.util.lerp( self.aimWeight, 1.0, blend )
		bobbing = 0.12
	else
		self.aimWeight = sm.util.lerp( self.aimWeight, 0.0, blend )
	end

	self.tool:updateCamera( 2.8, 30.0, vec3_new( 0.65, 0.0, 0.05 ), self.aimWeight )
	self.tool:updateFpCamera( 30.0, vec3_new( 0.0, 0.0, 0.0 ), self.aimWeight, bobbing )
end

function ZiplineGun:client_onEquip( animate )
	if animate then
		sm.audio.play( "PotatoRifle - Equip", self.tool:getPosition() )
	end

	self.wantEquipped = true
	self.aiming = false
	local cameraWeight, cameraFPWeight = self.tool:getCameraWeights()
	self.aimWeight = math.max( cameraWeight, cameraFPWeight )
	self.jointWeight = 0.0

	local currentRenderablesTp = {}
	local currentRenderablesFp = {}
	for k,v in pairs( renderablesTp ) do currentRenderablesTp[#currentRenderablesTp+1] = v end
	for k,v in pairs( renderablesFp ) do currentRenderablesFp[#currentRenderablesFp+1] = v end
	for k,v in pairs( renderables ) do
        currentRenderablesTp[#currentRenderablesTp+1] = v
        currentRenderablesFp[#currentRenderablesFp+1] = v
    end

	self.tool:setTpRenderables( currentRenderablesTp )
    if self.isLocal then
		self.tool:setFpRenderables( currentRenderablesFp )
    end

	self:loadAnimations()

	setTpAnimation( self.tpAnimations, "pickup", 0.0001 )
	if self.isLocal then
		swapFpAnimation( self.fpAnimations, "unequip", "equip", 0.2 )
	end
end

function ZiplineGun:client_onUnequip( animate )
	self.wantEquipped = false
	self.equipped = false
	self.aiming = false
	if sm.exists( self.tool ) then
		if animate then
			sm.audio.play( "PotatoRifle - Unequip", self.tool:getPosition() )
		end
		setTpAnimation( self.tpAnimations, "putdown" )
		if self.isLocal then
			self.tool:setMovementSlowDown( false )
			self.tool:setBlockSprint( false )
			self.tool:setCrossHairAlpha( 1.0 )
			self.tool:setInteractionTextSuppressed( false )
			if self.fpAnimations.currentAnimation ~= "unequip" then
				swapFpAnimation( self.fpAnimations, "equip", "unequip", 0.2 )
			end
		end
	end
end

function ZiplineGun:sv_n_onAim( aiming )
	self.network:sendToClients( "cl_n_onAim", aiming )
end

function ZiplineGun:cl_n_onAim( aiming )
	if not self.isLocal and self.tool:isEquipped() then
		self:onAim( aiming )
	end
end

function ZiplineGun:onAim( aiming )
	self.aiming = aiming
	if self.tpAnimations.currentAnimation == "idle" or self.tpAnimations.currentAnimation == "aim" or self.tpAnimations.currentAnimation == "relax" and self.aiming then
		setTpAnimation( self.tpAnimations, self.aiming and "aim" or "idle", 5.0 )
	end
end

local function CreatePole(data)
	if type(data[2]) == "Quat" then
		return sm.shape.createPart(ZIPLINEPOLE, data[1], data[2] --[[@as Quat]], false, true)
	else
		return data[4]:createPart(ZIPLINEPOLE, data[1], data[2] --[[@as Vec3]], data[3])
	end
end

---@param result RaycastResult
local function GetPoleData(result)
	local pole
	if result.type == "body" then
		local shape = result:getShape()
		if not shape.isBlock then return end

		local normal = sm.vec3.closestAxis( result.normalLocal )
		local position = result.pointLocal * 4 - result.normalLocal * 0.1
		position.x = math.floor( position.x )
		position.y = math.floor( position.y )
		position.z = math.floor( position.z )

		local xAxis
		if normal.x > 0 or normal.y > 0 or normal.z > 0 then
			position = position + normal
			xAxis = vec3_new( normal.z, normal.x, normal.y )
		else
			xAxis = vec3_new( -normal.y, -normal.z, -normal.x )
		end

		pole = { position, normal, xAxis, shape.body }
	else
		local gridPos, normal = result.pointWorld, result.normalWorld
		if normal == vec3_zero then return end

		pole = { gridPos - normal * 0.15, sm.vec3.getRotation(vec3_up, normal) }
	end

	return pole
end

function ZiplineGun:sv_n_onShoot(args, caller)
    if not IsSmallerAngle(args.dir, MAXZIPLINEANGLE) then
		return
	end

	local start = args.start
    local hit, result = sm.physics.raycast(start, start + args.dir * MAXZIPLINELENGTH, nil, ZIPLINESHOOTFILTER)
    local _type = result.type
    if _type == "unknown" then
        return
    end

    local char = self.tool:getOwner().character
    local charPos = char.worldPosition
    local groundHit, resultGround = sm.physics.raycast(charPos, charPos - char:getSurfaceNormal() * 2.5, nil, ZIPLINESHOOTFILTER)

    local preset = args.attachedPole
    local parent = preset or GetPoleData(resultGround)
    if not parent then return end

	local child = GetPoleData(result)
	if not child then return end

	if sm.game.getEnableAmmoConsumption() then
		sm.container.beginTransaction()
		sm.container.spend(caller:getInventory(), ZIPLINEPOLE, preset and 1 or 2)
		sm.container.endTransaction()
	end

	if not preset then
		parent = CreatePole(parent)
	end

	child = CreatePole(child)

    if preset then
        sm.event.sendToInteractable(preset.interactable, "sv_updateTarget", child)
    else
        parent.interactable:setParams({ target = child })
    end

	self.network:sendToClients( "cl_n_onShoot" )
end

function ZiplineGun:cl_n_onShoot()
	if not self.isLocal and self.tool:isEquipped() then
		self:onShoot()
	end
end

function ZiplineGun:onShoot()
	self.tpAnimations.animations.idle.time = 0
	self.tpAnimations.animations.shoot.time = 0
	self.tpAnimations.animations.aimShoot.time = 0

	setTpAnimation( self.tpAnimations, self.aiming and "aimShoot" or "shoot", 10.0 )
	if self.tool:isInFirstPersonView() then
		self.shootEffectFP:start()
	else
		self.shootEffect:start()
	end
end

function ZiplineGun:cl_onPrimaryUse( state )
	if self.fireCooldownTimer > 0.0 or state ~= 1 or not self.tool:getOwner().character:isOnGround() then return end

    if not sm.game.getEnableAmmoConsumption() or sm.container.canSpend( sm.localPlayer.getInventory(), ZIPLINEPOLE, self.attachedPole and 1 or 2 ) then
        local fireMode = self.aiming and self.aimFireMode or self.normalFireMode
        self.fireCooldownTimer = fireMode.fireCooldown
        self.spreadCooldownTimer = math.min( self.spreadCooldownTimer + fireMode.spreadIncrement, fireMode.spreadCooldown )
        self.sprintCooldownTimer = self.sprintCooldown

        self:onShoot()
        self.network:sendToServer( "sv_n_onShoot", { start = lplayer_getRayStart(), attachedPole = self.attachedPole, dir = sm.localPlayer.getDirection() } )

        setFpAnimation( self.fpAnimations, self.aiming and "aimShoot" or "shoot", 0.05 )

        self.attachedPole = nil
    else
        local fireMode = self.aiming and self.aimFireMode or self.normalFireMode
        self.fireCooldownTimer = fireMode.fireCooldown
        sm.audio.play( "PotatoRifle - NoAmmo" )
    end
end

function ZiplineGun:cl_onSecondaryUse( state )
    local aiming = state == 1 or state == 2
    if aiming ~= self.aiming then
        self.aiming = aiming
        self.tpAnimations.animations.idle.time = 0

		self:onAim( aiming )
		self.tool:setMovementSlowDown( aiming )
		self.network:sendToServer( "sv_n_onAim", aiming )
    end
end

local function InvalidPoint(result)
    local shape = result:getShape()
	return result.type ~= "terrainAsset" and result.type ~= "terrainSurface" and (not shape or not sm.item.isBlock(shape.uuid))
end

function ZiplineGun:client_onEquippedUpdate( primaryState, secondaryState, f )
    if not sm.exists(self.attachedPole) then
        self.attachedPole = nil
    end

	local rayStart, playerDir = lplayer_getRayStart(), lplayer_getDirection()
	local char = lplayer_get().character
    local aimHit, result = sm.physics.raycast(rayStart, rayStart + playerDir * MAXZIPLINELENGTH, char, ZIPLINESHOOTFILTERTRIGGERCHARACTER)
    local toPole = self.attachedPole and (result.pointWorld - GetPoleEnd(self.attachedPole))
    local distance = self.attachedPole and math.min(toPole:length(), MAXZIPLINELENGTH) or MAXZIPLINELENGTH * result.fraction
    local isInRange = distance < MAXZIPLINELENGTH

    local shape = result:getShape()
	local invalidAim = false
	if InvalidPoint(result) then
		invalidAim = true
	end

    local hit, result = sm.physics.spherecast(char.worldPosition, char.worldPosition - char:getSurfaceNormal() * char:getHeight() * 0.55, 0.25, char, ZIPLINESHOOTFILTERTRIGGERCHARACTER)
	local invalidGround = char:isSwimming() or char:isDiving()
	if InvalidPoint(result) then
		invalidGround = true
	end

	if invalidAim then
		sm.gui.displayAlertText("#ff0000Invalid #ffffffaim#ff0000 surface", 1)
	elseif invalidGround then
		sm.gui.displayAlertText("#ff0000Invalid #ffffffground#ff0000 surface", 1)
	else
		local dir = self.attachedPole and toPole:normalize() or playerDir
		local isInAngleRange, angle = IsSmallerAngle(dir, MAXZIPLINEANGLE)
		sm.gui.displayAlertText(
			("%s%.0fm\n#ffffffAngle: %s%.0f"):format(
				isInRange and "#ffffff" or "#ff0000",
				distance,
				isInAngleRange and "#00ff00" or "#ff0000",
				angle * (dir.z < 0 and -1 or 1)
			),
			1
		)

		if primaryState ~= self.prevPrimaryState then
			if aimHit and isInRange and isInAngleRange then
				self:cl_onPrimaryUse( primaryState )
			end

			self.prevPrimaryState = primaryState
		end

		if secondaryState ~= self.prevSecondaryState then
			self:cl_onSecondaryUse( secondaryState )
			self.prevSecondaryState = secondaryState
		end
	end


    if not self.attachedPole then
        if shape and shape.uuid == ZIPLINEPOLE then
            gui_setInteractionText("", ico_forcebuild, "Attach rope to pole")
            if f ~= self.prevF then
                if f then
                    self.attachedPole = shape
					--sm.gui.displayAlertText("Attached to pole", 2.5)
					sm.audio.play("PaintTool - ColorPick")
				end

                self.prevF = f
            end
        end
    else
        gui_setInteractionText("", ico_forcebuild, "Clear attached pole")
        if f ~= self.prevF then
            if f then
                self.attachedPole = nil
				--sm.gui.displayAlertText("Cleared pole", 2.5)
				sm.audio.play("PaintTool - ColorPick")
			end

            self.prevF = f
        end
    end

	return true, true
end