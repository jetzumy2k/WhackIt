--!strict
--[[
	Office furniture (docs/OFFICES.md). Every item is a few plain parts, built
	the same way on the server (placed furniture) and the client (placement
	preview) by Shared/FurnitureModel; no uploaded models.

	Tiers (owner decision 2026-10-09):
	  * Basic   - free and unlimited; only the room's MaxItems cap applies.
	  * Level   - level rewards (docs/GAMEPLAY_RULES.md "Level rewards"):
	    free and unlimited from MinLevel on. Already placed ones stay if the
	    level drops (an admin), but no new ones can be placed until it's back.
	  * Special - owned in counts (PlayerData.Furniture), from rewards: admin
	    rewards now, pickleball office-supply drops and quests later.

	Geometry: `Size` is the footprint (X width, Z depth) and height (Y) in
	studs; parts are positioned by `Offset`, the part's centre relative to
	the footprint's centre on the floor. The front of every item faces -Z
	(a chair's sitter, a screen, drawers). `Upright` turns a cylinder so its
	length (Size.X) is vertical. `Floor` items (rugs) can lie under other
	furniture but not under each other, and nobody bumps into them.
]]

export type Tier = "Basic" | "Level" | "Special"

export type PartSpec = {
	Name: string,
	Size: Vector3,
	Offset: Vector3,
	Color: Color3,
	Material: Enum.Material?,
	Shape: Enum.PartType?,
	Upright: boolean?,
	Transparency: number?,
	Text: string?, -- drawn on the front (-Z) face
}

export type Item = {
	Key: string,
	Name: string,
	Category: string,
	Tier: Tier,
	MinLevel: number?, -- Level tier only
	Size: Vector3,
	Floor: boolean?,
	Parts: { PartSpec },
}

export type Category = { Id: string, Label: string }

export type LayoutSeed = { Item: string, X: number, Z: number, R: number }

local WOOD = Color3.fromRGB(150, 105, 70)
local DARK_WOOD = Color3.fromRGB(105, 72, 48)
local METAL = Color3.fromRGB(120, 126, 138)
local DARK = Color3.fromRGB(45, 48, 58)
local WHITE = Color3.fromRGB(235, 236, 240)
local BLUE = Color3.fromRGB(70, 120, 200)
local SCREEN = Color3.fromRGB(110, 190, 255)
local LEAF = Color3.fromRGB(70, 150, 75)
local POT = Color3.fromRGB(190, 110, 70)
local FABRIC = Color3.fromRGB(95, 110, 160)
local PINK = Color3.fromRGB(240, 120, 170)
local GOLD = Color3.fromRGB(230, 185, 70)
local GREEN_LIGHT = Color3.fromRGB(110, 230, 140)

local NEON = Enum.Material.Neon
local CYLINDER = Enum.PartType.Cylinder
local BALL = Enum.PartType.Ball

local function p(
	name: string,
	size: Vector3,
	offset: Vector3,
	color: Color3,
	extra: { [string]: any }?
): PartSpec
	local spec: PartSpec = { Name = name, Size = size, Offset = offset, Color = color }
	if extra then
		spec.Material = extra.Material
		spec.Shape = extra.Shape
		spec.Upright = extra.Upright
		spec.Transparency = extra.Transparency
		spec.Text = extra.Text
	end
	return table.freeze(spec)
end

local V = Vector3.new

local categories: { Category } = {
	{ Id = "Desks", Label = "Desks & chairs" },
	{ Id = "Tech", Label = "Tech" },
	{ Id = "Storage", Label = "Plants & storage" },
	{ Id = "Decor", Label = "Decor" },
	{ Id = "Level", Label = "Level rewards" },
	{ Id = "Trophies", Label = "Trophies" },
}

local items: { Item } = {
	-- Desks & chairs -------------------------------------------------------
	{
		Key = "desk_basic",
		Name = "Desk",
		Category = "Desks",
		Tier = "Basic",
		Size = V(6, 3, 3),
		Parts = {
			p("Top", V(6, 0.4, 3), V(0, 2.8, 0), WOOD),
			p("Leg", V(0.3, 2.6, 0.3), V(-2.7, 1.3, -1.2), DARK_WOOD),
			p("Leg", V(0.3, 2.6, 0.3), V(2.7, 1.3, -1.2), DARK_WOOD),
			p("Leg", V(0.3, 2.6, 0.3), V(-2.7, 1.3, 1.2), DARK_WOOD),
			p("Leg", V(0.3, 2.6, 0.3), V(2.7, 1.3, 1.2), DARK_WOOD),
		},
	},
	{
		Key = "desk_wide",
		Name = "Big Desk",
		Category = "Desks",
		Tier = "Basic",
		Size = V(8, 3, 4),
		Parts = {
			p("Top", V(8, 0.4, 4), V(0, 2.8, 0), DARK_WOOD),
			p("Side", V(0.4, 2.6, 3.6), V(-3.7, 1.3, 0), DARK_WOOD),
			p("Side", V(0.4, 2.6, 3.6), V(3.7, 1.3, 0), DARK_WOOD),
			p("Panel", V(7, 1.6, 0.2), V(0, 1.8, 1.7), WOOD),
		},
	},
	{
		Key = "desk_standing",
		Name = "Standing Desk",
		Category = "Desks",
		Tier = "Basic",
		Size = V(5, 4.2, 2.5),
		Parts = {
			p("Top", V(5, 0.3, 2.5), V(0, 4.05, 0), WHITE),
			p(
				"Column",
				V(0.4, 3.9, 0.4),
				V(-2, 1.95, 0),
				METAL,
				{ Material = Enum.Material.Metal }
			),
			p("Column", V(0.4, 3.9, 0.4), V(2, 1.95, 0), METAL, { Material = Enum.Material.Metal }),
			p("Foot", V(0.6, 0.2, 2.3), V(-2, 0.1, 0), DARK),
			p("Foot", V(0.6, 0.2, 2.3), V(2, 0.1, 0), DARK),
		},
	},
	{
		Key = "chair_office",
		Name = "Office Chair",
		Category = "Desks",
		Tier = "Basic",
		Size = V(2.5, 4.6, 2.5),
		Parts = {
			p("Seat", V(2.2, 0.4, 2.2), V(0, 2, 0), DARK, { Material = Enum.Material.Fabric }),
			p("Back", V(2.2, 2.4, 0.3), V(0, 3.4, 1.05), DARK, { Material = Enum.Material.Fabric }),
			p("Post", V(0.3, 1.6, 0.3), V(0, 1, 0), METAL),
			p("Base", V(2.4, 0.2, 2.4), V(0, 0.1, 0), METAL),
		},
	},
	{
		Key = "chair_lounge",
		Name = "Lounge Chair",
		Category = "Desks",
		Tier = "Basic",
		Size = V(3, 3.4, 3),
		Parts = {
			p("Seat", V(2.6, 0.8, 2.6), V(0, 1, 0), FABRIC, { Material = Enum.Material.Fabric }),
			p(
				"Back",
				V(2.6, 2.2, 0.5),
				V(0, 2.3, 1.2),
				FABRIC,
				{ Material = Enum.Material.Fabric }
			),
			p(
				"Arm",
				V(0.4, 1.4, 2.6),
				V(-1.3, 1.5, 0),
				FABRIC,
				{ Material = Enum.Material.Fabric }
			),
			p("Arm", V(0.4, 1.4, 2.6), V(1.3, 1.5, 0), FABRIC, { Material = Enum.Material.Fabric }),
		},
	},
	{
		Key = "sofa",
		Name = "Sofa",
		Category = "Desks",
		Tier = "Basic",
		Size = V(7, 3, 3),
		Parts = {
			p("Base", V(7, 1, 3), V(0, 0.7, 0), FABRIC, { Material = Enum.Material.Fabric }),
			p("Back", V(7, 2, 0.6), V(0, 2, 1.2), FABRIC, { Material = Enum.Material.Fabric }),
			p("Arm", V(0.6, 1.6, 3), V(-3.2, 1.4, 0), FABRIC, { Material = Enum.Material.Fabric }),
			p("Arm", V(0.6, 1.6, 3), V(3.2, 1.4, 0), FABRIC, { Material = Enum.Material.Fabric }),
			p(
				"Cushion",
				V(2.9, 0.4, 2.2),
				V(-1.5, 1.4, -0.3),
				BLUE,
				{ Material = Enum.Material.Fabric }
			),
			p(
				"Cushion",
				V(2.9, 0.4, 2.2),
				V(1.5, 1.4, -0.3),
				BLUE,
				{ Material = Enum.Material.Fabric }
			),
		},
	},
	{
		Key = "bean_bag",
		Name = "Bean Bag",
		Category = "Desks",
		Tier = "Basic",
		Size = V(3, 2.4, 3),
		Parts = {
			p(
				"Bag",
				V(2.4, 2.4, 2.4),
				V(0, 1.2, 0),
				PINK,
				{ Shape = BALL, Material = Enum.Material.Fabric }
			),
		},
	},

	-- Tech -------------------------------------------------------------------
	{
		Key = "workstation",
		Name = "Computer Desk",
		Category = "Tech",
		Tier = "Basic",
		Size = V(6, 4.8, 3),
		Parts = {
			p("Top", V(6, 0.4, 3), V(0, 2.8, 0), WOOD),
			p("Side", V(0.4, 2.6, 2.8), V(-2.8, 1.3, 0), DARK_WOOD),
			p("Side", V(0.4, 2.6, 2.8), V(2.8, 1.3, 0), DARK_WOOD),
			p("Monitor", V(2.6, 1.5, 0.2), V(0, 4, 0.9), DARK),
			p(
				"Screen",
				V(2.4, 1.3, 0.05),
				V(0, 4, 0.78),
				SCREEN,
				{ Material = NEON, Transparency = 0.2 }
			),
			p("Stand", V(0.3, 0.6, 0.3), V(0, 3.3, 1), DARK),
			p("Keyboard", V(1.8, 0.1, 0.6), V(0, 3.05, -0.4), DARK),
		},
	},
	{
		Key = "printer",
		Name = "Printer",
		Category = "Tech",
		Tier = "Basic",
		Size = V(2.5, 3.2, 2),
		Parts = {
			p("Stand", V(2.4, 2.2, 1.9), V(0, 1.1, 0), METAL),
			p("Printer", V(2.2, 0.9, 1.7), V(0, 2.65, 0), WHITE),
			p("Paper", V(1.4, 0.1, 0.6), V(0, 3.15, 0.4), Color3.new(1, 1, 1)),
		},
	},
	{
		Key = "server_rack",
		Name = "Server Rack",
		Category = "Tech",
		Tier = "Basic",
		Size = V(2.5, 6, 2.5),
		Parts = {
			p("Body", V(2.4, 6, 2.4), V(0, 3, 0), DARK, { Material = Enum.Material.Metal }),
			p("Lights", V(2, 0.15, 0.05), V(0, 2, -1.22), GREEN_LIGHT, { Material = NEON }),
			p("Lights", V(2, 0.15, 0.05), V(0, 3.2, -1.22), GREEN_LIGHT, { Material = NEON }),
			p("Lights", V(2, 0.15, 0.05), V(0, 4.4, -1.22), GREEN_LIGHT, { Material = NEON }),
		},
	},
	{
		Key = "water_cooler",
		Name = "Water Cooler",
		Category = "Tech",
		Tier = "Basic",
		Size = V(2, 4.6, 2),
		Parts = {
			p("Body", V(1.6, 3, 1.6), V(0, 1.5, 0), WHITE),
			p("Bottle", V(1.6, 1.4, 1.4), V(0, 3.8, 0), SCREEN, {
				Shape = CYLINDER,
				Upright = true,
				Material = Enum.Material.Glass,
				Transparency = 0.3,
			}),
			p("Tap", V(0.3, 0.3, 0.3), V(0, 2.4, -0.85), BLUE),
		},
	},
	{
		Key = "coffee_station",
		Name = "Coffee Station",
		Category = "Tech",
		Tier = "Basic",
		Size = V(4, 4.2, 2),
		Parts = {
			p("Counter", V(4, 2.8, 2), V(0, 1.4, 0), DARK_WOOD),
			p(
				"Machine",
				V(1.4, 1.4, 1.2),
				V(-0.9, 3.5, 0.2),
				DARK,
				{ Material = Enum.Material.Metal }
			),
			p("Mug", V(0.3, 0.4, 0.3), V(-0.9, 3, -0.5), WHITE),
			p("Mug", V(0.3, 0.4, 0.3), V(0.8, 3, -0.4), BLUE),
			p("Mug", V(0.3, 0.4, 0.3), V(1.3, 3, -0.4), PINK),
		},
	},
	{
		Key = "tv_screen",
		Name = "Big Screen TV",
		Category = "Tech",
		Tier = "Basic",
		Size = V(6, 4.8, 1.5),
		Parts = {
			p("Frame", V(5.6, 3.2, 0.3), V(0, 3.2, 0.2), DARK),
			p(
				"Screen",
				V(5.4, 3, 0.05),
				V(0, 3.2, 0.03),
				SCREEN,
				{ Material = NEON, Transparency = 0.35 }
			),
			p("Stand", V(0.4, 1.6, 0.4), V(0, 0.8, 0.4), DARK),
			p("Foot", V(2.4, 0.2, 1.4), V(0, 0.1, 0), DARK),
		},
	},
	{
		Key = "arcade",
		Name = "Arcade Machine",
		Category = "Tech",
		Tier = "Basic",
		Size = V(3, 6, 3),
		Parts = {
			p("Cabinet", V(2.8, 6, 2.6), V(0, 3, 0.1), Color3.fromRGB(120, 60, 170)),
			p(
				"Screen",
				V(2.2, 1.6, 0.05),
				V(0, 4.4, -1.22),
				SCREEN,
				{ Material = NEON, Transparency = 0.2 }
			),
			p("Controls", V(2.6, 0.3, 0.8), V(0, 3.2, -1.05), DARK),
			p(
				"Sign",
				V(2.6, 0.6, 0.05),
				V(0, 5.6, -1.22),
				PINK,
				{ Material = NEON, Text = "WHACK!" }
			),
		},
	},

	-- Plants & storage -------------------------------------------------------
	{
		Key = "plant_small",
		Name = "Small Plant",
		Category = "Storage",
		Tier = "Basic",
		Size = V(2, 2.8, 2),
		Parts = {
			p("Pot", V(1.2, 1.4, 1.4), V(0, 0.6, 0), POT, { Shape = CYLINDER, Upright = true }),
			p(
				"Leaves",
				V(2, 2, 2),
				V(0, 1.8, 0),
				LEAF,
				{ Shape = BALL, Material = Enum.Material.Grass }
			),
		},
	},
	{
		Key = "plant_tall",
		Name = "Tall Plant",
		Category = "Storage",
		Tier = "Basic",
		Size = V(3, 6, 3),
		Parts = {
			p("Pot", V(1.6, 2, 2), V(0, 0.8, 0), POT, { Shape = CYLINDER, Upright = true }),
			p("Stem", V(0.3, 3, 0.3), V(0, 3, 0), DARK_WOOD),
			p(
				"Leaves",
				V(2.4, 2.4, 2.4),
				V(0, 4.6, 0),
				LEAF,
				{ Shape = BALL, Material = Enum.Material.Grass }
			),
			p(
				"Leaves",
				V(1.8, 1.8, 1.8),
				V(-0.6, 3.6, 0.4),
				LEAF,
				{ Shape = BALL, Material = Enum.Material.Grass }
			),
			p(
				"Leaves",
				V(1.8, 1.8, 1.8),
				V(0.6, 3.8, -0.4),
				LEAF,
				{ Shape = BALL, Material = Enum.Material.Grass }
			),
		},
	},
	{
		Key = "filing_cabinet",
		Name = "Filing Cabinet",
		Category = "Storage",
		Tier = "Basic",
		Size = V(2, 4.2, 2.5),
		Parts = {
			p("Body", V(1.8, 4.2, 2.2), V(0, 2.1, 0), METAL, { Material = Enum.Material.Metal }),
			p("Drawer", V(1.5, 1, 0.1), V(0, 0.9, -1.12), WHITE),
			p("Drawer", V(1.5, 1, 0.1), V(0, 2.1, -1.12), WHITE),
			p("Drawer", V(1.5, 1, 0.1), V(0, 3.3, -1.12), WHITE),
		},
	},
	{
		Key = "bookshelf",
		Name = "Bookshelf",
		Category = "Storage",
		Tier = "Basic",
		Size = V(5, 7, 1.6),
		Parts = {
			p("Back", V(5, 7, 0.2), V(0, 3.5, 0.7), DARK_WOOD),
			p("Side", V(0.3, 7, 1.6), V(-2.35, 3.5, 0), DARK_WOOD),
			p("Side", V(0.3, 7, 1.6), V(2.35, 3.5, 0), DARK_WOOD),
			p("Shelf", V(4.4, 0.2, 1.4), V(0, 1.6, 0), WOOD),
			p("Shelf", V(4.4, 0.2, 1.4), V(0, 3.6, 0), WOOD),
			p("Shelf", V(4.4, 0.2, 1.4), V(0, 5.6, 0), WOOD),
			p("Books", V(3.8, 1.2, 1.1), V(0, 2.3, 0), BLUE),
			p("Books", V(3.8, 1.2, 1.1), V(0, 4.3, 0), Color3.fromRGB(200, 90, 80)),
			p("Books", V(3.8, 1.2, 1.1), V(0, 6.3, 0), GREEN_LIGHT:Lerp(LEAF, 0.6)),
		},
	},

	-- Decor ------------------------------------------------------------------
	{
		Key = "rug_round",
		Name = "Round Rug",
		Category = "Decor",
		Tier = "Basic",
		Size = V(6, 0.2, 6),
		Floor = true,
		Parts = {
			p(
				"Rug",
				V(0.2, 6, 6),
				V(0, 0.1, 0),
				PINK,
				{ Shape = CYLINDER, Upright = true, Material = Enum.Material.Fabric }
			),
		},
	},
	{
		Key = "rug_rect",
		Name = "Office Rug",
		Category = "Decor",
		Tier = "Basic",
		Size = V(8, 0.2, 5),
		Floor = true,
		Parts = {
			p("Rug", V(8, 0.15, 5), V(0, 0.075, 0), FABRIC, { Material = Enum.Material.Fabric }),
			p("Inner", V(7, 0.2, 4), V(0, 0.1, 0), BLUE, { Material = Enum.Material.Fabric }),
		},
	},
	{
		Key = "floor_lamp",
		Name = "Floor Lamp",
		Category = "Decor",
		Tier = "Basic",
		Size = V(2, 6, 2),
		Parts = {
			p("Base", V(0.3, 1.6, 1.6), V(0, 0.15, 0), DARK, { Shape = CYLINDER, Upright = true }),
			p("Pole", V(0.2, 5, 0.2), V(0, 2.8, 0), METAL),
			p(
				"Shade",
				V(1.2, 1.6, 1.6),
				V(0, 5.4, 0),
				Color3.fromRGB(255, 235, 190),
				{ Shape = CYLINDER, Upright = true }
			),
		},
	},
	{
		Key = "whiteboard",
		Name = "Whiteboard",
		Category = "Decor",
		Tier = "Basic",
		Size = V(5, 5.5, 1.5),
		Parts = {
			p("Board", V(4.8, 3, 0.2), V(0, 4, 0), WHITE, { Text = "TODO: relax" }),
			p("Leg", V(0.2, 5.5, 0.2), V(-2.3, 2.75, 0), METAL),
			p("Leg", V(0.2, 5.5, 0.2), V(2.3, 2.75, 0), METAL),
			p("Foot", V(0.3, 0.2, 1.4), V(-2.3, 0.1, 0), METAL),
			p("Foot", V(0.3, 0.2, 1.4), V(2.3, 0.1, 0), METAL),
			p("Tray", V(4, 0.15, 0.4), V(0, 2.4, -0.2), METAL),
		},
	},
	{
		Key = "stress_ball",
		Name = "Giant Stress Ball",
		Category = "Decor",
		Tier = "Basic",
		Size = V(3, 3, 3),
		Parts = {
			p("Ball", V(3, 3, 3), V(0, 1.5, 0), PINK, { Shape = BALL }),
		},
	},
	{
		Key = "coat_rack",
		Name = "Coat Rack",
		Category = "Decor",
		Tier = "Basic",
		Size = V(2, 6, 2),
		Parts = {
			p(
				"Base",
				V(0.3, 1.6, 1.6),
				V(0, 0.15, 0),
				DARK_WOOD,
				{ Shape = CYLINDER, Upright = true }
			),
			p("Pole", V(0.25, 5.6, 0.25), V(0, 3, 0), DARK_WOOD),
			p("Hook", V(1.2, 0.15, 0.15), V(0, 5.3, 0), DARK_WOOD),
			p("Hook", V(0.15, 0.15, 1.2), V(0, 5, 0), DARK_WOOD),
			p("Coat", V(0.9, 1.8, 0.5), V(0.4, 4.2, 0), BLUE, { Material = Enum.Material.Fabric }),
		},
	},
	{
		Key = "poster_easel",
		Name = "Motivational Poster",
		Category = "Decor",
		Tier = "Basic",
		Size = V(3, 5.4, 1),
		Parts = {
			p("Leg", V(0.2, 5, 0.2), V(-1.2, 2.5, 0.3), WOOD),
			p("Leg", V(0.2, 5, 0.2), V(1.2, 2.5, 0.3), WOOD),
			p(
				"Poster",
				V(2.6, 3.4, 0.1),
				V(0, 3.6, 0.1),
				Color3.fromRGB(70, 90, 150),
				{ Text = "Breathe in. Whack out." }
			),
		},
	},

	-- Level rewards (Level tier) ----------------------------------------------
	{
		Key = "desk_executive",
		Name = "Executive Desk",
		Category = "Level",
		Tier = "Level",
		MinLevel = 20,
		Size = V(7, 3.6, 3.5),
		Parts = {
			p("Top", V(7, 0.4, 3.5), V(0, 2.9, 0), DARK_WOOD),
			p("Trim", V(7, 0.1, 3.5), V(0, 3.15, 0), GOLD, { Material = Enum.Material.Metal }),
			p("Front", V(6.6, 2.7, 0.3), V(0, 1.35, -1.55), DARK_WOOD),
			p("Side", V(0.4, 2.7, 3.2), V(-3.25, 1.35, 0), DARK_WOOD),
			p("Side", V(0.4, 2.7, 3.2), V(3.25, 1.35, 0), DARK_WOOD),
			p(
				"Nameplate",
				V(1.6, 0.4, 0.3),
				V(0, 3.4, -1.3),
				GOLD,
				{ Material = Enum.Material.Metal }
			),
		},
	},
	{
		Key = "aquarium",
		Name = "Aquarium",
		Category = "Level",
		Tier = "Level",
		MinLevel = 30,
		Size = V(5, 4.6, 2),
		Parts = {
			p("Stand", V(5, 2, 2), V(0, 1, 0), DARK),
			p(
				"Tank",
				V(4.8, 2.4, 1.8),
				V(0, 3.2, 0),
				SCREEN,
				{ Material = Enum.Material.Glass, Transparency = 0.6 }
			),
			p("Water", V(4.6, 1.8, 1.6), V(0, 3.05, 0), BLUE, { Transparency = 0.5 }),
			p(
				"Fish",
				V(0.6, 0.35, 0.15),
				V(-1, 3.2, 0),
				Color3.fromRGB(255, 150, 60),
				{ Material = NEON }
			),
			p(
				"Fish",
				V(0.5, 0.3, 0.15),
				V(1.2, 3.6, 0.3),
				Color3.fromRGB(255, 220, 90),
				{ Material = NEON }
			),
			p("Lid", V(5, 0.2, 2), V(0, 4.5, 0), DARK),
		},
	},
	{
		Key = "zen_fountain",
		Name = "Zen Fountain",
		Category = "Level",
		Tier = "Level",
		MinLevel = 50,
		Size = V(3, 3, 3),
		Parts = {
			p(
				"Basin",
				V(1, 3, 3),
				V(0, 0.5, 0),
				Color3.fromRGB(150, 150, 145),
				{ Shape = CYLINDER, Upright = true, Material = Enum.Material.Slate }
			),
			p(
				"Water",
				V(0.1, 2.6, 2.6),
				V(0, 1.02, 0),
				SCREEN,
				{ Shape = CYLINDER, Upright = true, Transparency = 0.3 }
			),
			p(
				"Stone",
				V(1.2, 1.2, 1.2),
				V(0, 1.6, 0),
				Color3.fromRGB(120, 120, 115),
				{ Shape = BALL, Material = Enum.Material.Slate }
			),
			p(
				"Stone",
				V(0.8, 0.8, 0.8),
				V(0, 2.5, 0),
				Color3.fromRGB(140, 140, 135),
				{ Shape = BALL, Material = Enum.Material.Slate }
			),
		},
	},
	{
		Key = "golden_statue",
		Name = "Golden Hammer Statue",
		Category = "Level",
		Tier = "Level",
		MinLevel = 100,
		Size = V(2.5, 6.5, 2.5),
		Parts = {
			p(
				"Pedestal",
				V(2.4, 1.6, 2.4),
				V(0, 0.8, 0),
				WHITE,
				{ Material = Enum.Material.Marble }
			),
			p("Handle", V(0.5, 3.4, 0.5), V(0, 3.3, 0), GOLD, { Material = Enum.Material.Metal }),
			p("Head", V(2.4, 1.4, 1.2), V(0, 5.7, 0), GOLD, { Material = Enum.Material.Metal }),
		},
	},

	-- Trophies (Special) -----------------------------------------------------
	{
		Key = "trophy_gold",
		Name = "Golden Hammer Trophy",
		Category = "Trophies",
		Tier = "Special",
		Size = V(2, 3, 2),
		Parts = {
			p("Base", V(1.6, 0.8, 1.6), V(0, 0.4, 0), DARK_WOOD),
			p("Handle", V(0.3, 1.2, 0.3), V(0, 1.4, 0), GOLD, { Material = Enum.Material.Metal }),
			p("Head", V(1.6, 0.7, 0.8), V(0, 2.35, 0), GOLD, { Material = Enum.Material.Metal }),
		},
	},
	{
		Key = "bonsai_zen",
		Name = "Zen Bonsai",
		Category = "Trophies",
		Tier = "Special",
		Size = V(2, 2.8, 2),
		Parts = {
			p("Tray", V(1.8, 0.4, 1.4), V(0, 0.2, 0), DARK),
			p("Trunk", V(0.3, 1.2, 0.3), V(0, 1, 0), DARK_WOOD),
			p(
				"Leaves",
				V(1.4, 1.4, 1.4),
				V(-0.3, 1.9, 0),
				LEAF,
				{ Shape = BALL, Material = Enum.Material.Grass }
			),
			p(
				"Leaves",
				V(1, 1, 1),
				V(0.4, 2.2, 0),
				LEAF,
				{ Shape = BALL, Material = Enum.Material.Grass }
			),
		},
	},
	{
		Key = "champion_plaque",
		Name = "Champion Plaque",
		Category = "Trophies",
		Tier = "Special",
		Size = V(2, 4.2, 1.6),
		Parts = {
			p("Base", V(1.2, 0.2, 0.8), V(0, 0.1, 0.2), DARK_WOOD),
			p("Stand", V(0.3, 3, 0.3), V(0, 1.5, 0.2), DARK_WOOD),
			p(
				"Plaque",
				V(1.8, 1.2, 0.15),
				V(0, 3.4, 0),
				GOLD,
				{ Material = Enum.Material.Metal, Text = "CHAMPION" }
			),
		},
	},
}

local byKey: { [string]: Item } = {}
local categoryIds: { [string]: boolean } = {}
for _, category in categories do
	categoryIds[category.Id] = true
	table.freeze(category)
end
for _, item in items do
	assert(byKey[item.Key] == nil, "duplicate furniture key " .. item.Key)
	assert(categoryIds[item.Category], "unknown furniture category " .. item.Category)
	table.freeze(item.Parts)
	byKey[item.Key] = table.freeze(item)
end

local FurnitureConfig = table.freeze({
	Categories = table.freeze(categories),
	List = table.freeze(items),
	ByKey = table.freeze(byKey),
	MaxPartsPerItem = 12,
	-- Most of one Special item a player can own (bounds saved data).
	MaxOwnedSpecial = 1000,
	-- Every new office starts with these (room-local, OfficeConfig): a computer
	-- desk against the back wall facing the room, its chair, a plant.
	DefaultLayout = table.freeze({
		table.freeze({ Item = "workstation", X = 0, Z = -16, R = 180 }),
		table.freeze({ Item = "chair_office", X = 0, Z = -12, R = 0 }),
		table.freeze({ Item = "plant_small", X = -16, Z = -16, R = 0 }),
	} :: { LayoutSeed }),
})

return FurnitureConfig
