--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Validate = require(ReplicatedStorage.Shared.Validate)

local NAN = 0 / 0

return function()
	describe("Validate.string", function()
		it("accepts a non-empty string within the length limit", function()
			expect(Validate.string("hello", 10)).to.equal("hello")
			expect(Validate.string("abc", 3)).to.equal("abc")
		end)

		it("rejects non-strings", function()
			expect(Validate.string(5, 10)).to.equal(nil)
			expect(Validate.string(nil, 10)).to.equal(nil)
			expect(Validate.string({}, 10)).to.equal(nil)
			expect(Validate.string(true, 10)).to.equal(nil)
		end)

		it("rejects empty and over-long strings", function()
			expect(Validate.string("", 10)).to.equal(nil)
			expect(Validate.string("abcd", 3)).to.equal(nil)
			expect(Validate.string(string.rep("x", 100000), 64)).to.equal(nil)
		end)

		it("rejects malformed UTF-8", function()
			expect(Validate.string("bad\255bytes", 64)).to.equal(nil)
		end)
	end)

	describe("Validate.id", function()
		it("accepts letters, digits, underscore and hyphen", function()
			expect(Validate.id("boss_12-a", 64)).to.equal("boss_12-a")
		end)

		it("rejects other characters", function()
			expect(Validate.id("boss 1", 64)).to.equal(nil)
			expect(Validate.id("boss/../1", 64)).to.equal(nil)
			expect(Validate.id("boss\n1", 64)).to.equal(nil)
		end)

		it("rejects non-strings and over-long ids", function()
			expect(Validate.id(1, 64)).to.equal(nil)
			expect(Validate.id(string.rep("a", 65), 64)).to.equal(nil)
		end)
	end)

	describe("Validate.number", function()
		it("accepts finite numbers within range, inclusive", function()
			expect(Validate.number(5, 0, 10)).to.equal(5)
			expect(Validate.number(0, 0, 10)).to.equal(0)
			expect(Validate.number(10, 0, 10)).to.equal(10)
			expect(Validate.number(2.5, 0, 10)).to.equal(2.5)
		end)

		it("rejects NaN and infinities", function()
			expect(Validate.number(NAN, -math.huge, math.huge)).to.equal(nil)
			expect(Validate.number(math.huge, -math.huge, math.huge)).to.equal(nil)
			expect(Validate.number(-math.huge, -math.huge, math.huge)).to.equal(nil)
		end)

		it("rejects out-of-range, huge and negative values", function()
			expect(Validate.number(-1, 0, 10)).to.equal(nil)
			expect(Validate.number(11, 0, 10)).to.equal(nil)
			expect(Validate.number(1e308, 0, 10)).to.equal(nil)
		end)

		it("rejects numeric strings and other types", function()
			expect(Validate.number("5", 0, 10)).to.equal(nil)
			expect(Validate.number(nil, 0, 10)).to.equal(nil)
			expect(Validate.number(true, 0, 10)).to.equal(nil)
		end)
	end)

	describe("Validate.integer", function()
		it("accepts whole numbers in range", function()
			expect(Validate.integer(3, 0, 10)).to.equal(3)
		end)

		it("rejects fractions, NaN and out-of-range values", function()
			expect(Validate.integer(3.5, 0, 10)).to.equal(nil)
			expect(Validate.integer(NAN, 0, 10)).to.equal(nil)
			expect(Validate.integer(11, 0, 10)).to.equal(nil)
		end)
	end)

	describe("Validate.boolean", function()
		it("accepts booleans, including false", function()
			expect(Validate.boolean(true)).to.equal(true)
			expect(Validate.boolean(false)).to.equal(false)
		end)

		it("rejects truthy non-booleans", function()
			expect(Validate.boolean(1)).to.equal(nil)
			expect(Validate.boolean("true")).to.equal(nil)
		end)
	end)
end
