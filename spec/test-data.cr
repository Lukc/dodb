require "uuid"
require "json"

# FIXME: Split the test data in separate files. We don’t care about those here.

class Ship
	include JSON::Serializable

	def_clone

	property id    : String
	property klass : String
	property name  : String
	property tags  : Array(String)

	def initialize(@name, @klass = "<unknown>", @id = UUID.random.to_s, @tags = [] of String)
	end

	# Makes testing arrays of this class easier.
	def <=>(other)
		@name <=> other.name
	end

	# Common, reusable test data.
	# Those data can be indexed, partitioned or tagged on different parameters,
	# and can easily be extended.

	class_getter kisaragi = Ship.new("Kisaragi", "Mutsuki")
	class_getter mutsuki  = Ship.new("Mutsuki",  "Mutsuki", tags: ["name ship"])
	class_getter yayoi    = Ship.new("Yayoi",    "Mutsuki")
	class_getter destroyers = [
		@@mutsuki,
		@@kisaragi,
		@@yayoi,
		Ship.new("Uzuki",    "Mutsuki"),
		Ship.new("Satsuki",  "Mutsuki"),

		Ship.new("Shiratsuyu", "Shiratsuyu", tags: ["name ship"]),
		Ship.new("Murasame",   "Shiratsuyu"),
		Ship.new("Yuudachi",   "Shiratsuyu")
	]

	class_getter yamato = 
		Ship.new("Yamato",    "Yamato",      tags: ["name ship", "flagship"])
	class_getter flagship : Ship = yamato
	class_getter battleships = [
		@@yamato,
		Ship.new("Kongou",    "Kongou",      tags: ["name ship"]),
		Ship.new("Haruna",    "Kongou"),
		Ship.new("Kirishima", "Kongou"),
		Ship.new("Hiei"     , "Kongou"),
		Ship.new("Musashi",   "Yamato"),
		Ship.new("Shinano",   "Yamato")
	]

	class_getter all_ships : Array(Ship) = @@destroyers + @@battleships

	# Equality is true if every property is identical.
	def ==(other)
		@id == other.id && @klass == other.klass && @name == other.name &&
			@tags == other.tags
	end
end

# This will be used for migration testing, but basically it’s a variant of
# the class above, a few extra fields, a few missing ones.
class PrimitiveShip
	include JSON::Serializable

	property id         : String
	property name       : String
	property wooden     : Bool   = false # Will be removed.
	property class_name : String         # Will be renamed
	property flagship   : Bool   = false # Will be moved to tags.

	def initialize(@name, @class_name = "<unknown>", @id = UUID.random.to_s, @flagship = false)
	end

	class_getter kamikaze =
		PrimitiveShip.new("Kamikaze", "Kamikaze")
	class_getter asakaze =
		PrimitiveShip.new("Asakaze",  "Kamikaze")
	class_getter all_ships : Array(PrimitiveShip) = [
		@@kamikaze,
		@@asakaze
	]
end
