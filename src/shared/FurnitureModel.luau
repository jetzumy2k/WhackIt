--!strict
--[[
	Builds a furniture Model from its FurnitureConfig entry (docs/OFFICES.md).
	Used by the server for placed furniture and by the client for the
	placement preview, so the preview is exactly what will appear.

	The Model's pivot is the centre of its footprint on the floor, front
	facing -Z, so placing is `model:PivotTo(roomFloor * CFrame.new(x, 0, z) *
	CFrame.Angles(0, math.rad(r), 0))`. Every part is anchored, can't be
	touched, and only solid furniture collides (rugs don't).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FurnitureConfig = require(ReplicatedStorage.Config.FurnitureConfig)

local FurnitureModel = {}

FurnitureModel.ITEM_ATTRIBUTE = "FurnitureItem"

-- The part's size along the world axes once placed in its model (an Upright
-- cylinder's length runs up, so its X and Y swap).
function FurnitureModel.extents(spec: FurnitureConfig.PartSpec): Vector3
	if spec.Upright then
		return Vector3.new(spec.Size.Y, spec.Size.X, spec.Size.Z)
	end
	return spec.Size
end

local function label(part: BasePart, text: string): ()
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0.6
	gui.Parent = part
	local textLabel = Instance.new("TextLabel")
	textLabel.BackgroundTransparency = 1
	textLabel.Size = UDim2.fromScale(1, 1)
	textLabel.Font = Enum.Font.FredokaOne
	textLabel.TextScaled = true
	textLabel.TextWrapped = true
	textLabel.TextColor3 = Color3.fromRGB(255, 240, 200)
	textLabel.Text = text
	textLabel.Parent = gui
end

function FurnitureModel.build(item: FurnitureConfig.Item): Model
	local model = Instance.new("Model")
	model.Name = item.Key
	for _, spec in item.Parts do
		local part = Instance.new("Part")
		part.Name = spec.Name
		part.Shape = spec.Shape or Enum.PartType.Block
		part.Size = spec.Size
		local cframe = CFrame.new(spec.Offset)
		if spec.Upright then
			cframe *= CFrame.Angles(0, 0, math.rad(90))
		end
		part.CFrame = cframe
		part.Color = spec.Color
		part.Material = spec.Material or Enum.Material.SmoothPlastic
		part.Transparency = spec.Transparency or 0
		part.Anchored = true
		part.CanCollide = not item.Floor
		part.CanTouch = false
		part.CastShadow = not item.Floor
		part.TopSurface = Enum.SurfaceType.Smooth
		part.BottomSurface = Enum.SurfaceType.Smooth
		if spec.Text then
			label(part, spec.Text)
		end
		part.Parent = model
	end
	model.WorldPivot = CFrame.identity
	model:SetAttribute(FurnitureModel.ITEM_ATTRIBUTE, item.Key)
	return model
end

-- Where a placed item's pivot goes, given the room's floor centre.
function FurnitureModel.placement(floorCentre: CFrame, x: number, z: number, r: number): CFrame
	return floorCentre * CFrame.new(x, 0, z) * CFrame.Angles(0, math.rad(r), 0)
end

return FurnitureModel
