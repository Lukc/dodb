require "spec"
require "file_utils"
require "json"
require "uuid"

require "../src/*"

class Ship
	include JSON::Serializable

	def_clone

	property id    : String
	property class : String
	property name  : String
	property tags  : Array(String)

	def initialize(@name, @class = "<unknown>", @id = UUID.random.to_s, @tags = [] of String)
	end

	# Common, reusable test data.
	# Those data can be indexed, partitioned or tagged on different parameters,
	# and can easily be extended.

	class_getter kisaragi = Ship.new("Kisaragi", "Mutsuki")
	class_getter destroyers = [
		@@kisaragi,
		Ship.new("Mutsuki",  "Mutsuki",      tags: ["name ship"]),
		Ship.new("Yayoi",    "Mutsuki"),
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
		@id == other.id && @class == other.class && @name == other.name &&
			@tags == other.tags
	end
end

class DODB::SpecDataBase < DODB::DataBase(String, Ship)
	def initialize
		::FileUtils.rm_rf "test-storage"

		initialize "test-storage"
	end
end

describe "DODB::DataBase" do
	describe "basics" do
		it "store and get data" do
			db = DODB::SpecDataBase.new

			Ship.all_ships.each do |ship|
				db[ship.id] = ship
			end

			Ship.all_ships.each do |ship|
				db[ship.id].should eq(ship)
			end
		end

		it "rewrite already stored data" do
			db = DODB::SpecDataBase.new
			ship = Ship.all_ships[0]

			db[ship.id] = Ship.new "broken", id: ship.id
			db[ship.id] = ship

			db[ship.id].should eq(ship)
		end

		it "properly remove data" do
			db = DODB::SpecDataBase.new

			Ship.all_ships.each do |ship|
				db[ship.id] = ship
			end

			Ship.all_ships.each do |ship|
				db.delete ship.id
			end

			Ship.all_ships.each do |ship|
				# FIXME: Should it raise a particular exception?
				expect_raises DODB::MissingEntry do
					db[ship.id]
				end

				db[ship.id]?.should be_nil
			end
		end
	end

	describe "indices" do
		it "do basic indexing" do
			db = DODB::SpecDataBase.new

			db_ships_by_name = db.new_index "name", &.name

			Ship.all_ships.each do |ship|
				db[ship.id] = ship
			end

			Ship.all_ships.each do |ship|
				db_ships_by_name.get?(ship.name).should eq(ship)
			end
		end

		it "raise on index overload" do
			db = DODB::SpecDataBase.new

			db_ships_by_name = db.new_index "name", &.name

			some_ship = Ship.kisaragi

			db[some_ship.id] = some_ship

			# Should not be allowed to store an entry whose “name” field
			# already exists.
			expect_raises(DODB::IndexOverload) do
				db["another id"] = some_ship
			end
		end

		it "properly deindex" do
			db = DODB::SpecDataBase.new

			db_ships_by_name = db.new_index "name", &.name

			Ship.all_ships.each do |ship|
				db[ship.id] = ship
			end

			Ship.all_ships.each do |ship|
				db.delete ship.id
			end

			Ship.all_ships.each do |ship|
				db_ships_by_name.get?(ship.name).should be_nil
			end
		end

		it "properly reindex" do
			db = DODB::SpecDataBase.new

			db_ships_by_name = db.new_index "name", &.name

			some_ship = Ship.kisaragi

			db[some_ship.id] = some_ship

			# We give the old id to the new ship, to get it replaced in
			# the database.
			some_new_ship = Ship.all_ships[2].clone
			some_new_ship.id = some_ship.id

			db[some_new_ship.id] = some_new_ship

			db[some_new_ship.id].should eq(some_new_ship)

			db_ships_by_name.get?(some_new_ship.name).should eq(some_new_ship)
		end
	end

	describe "partitions" do
		it "do basic partitioning" do
			db = DODB::SpecDataBase.new

			db_ships_by_class = db.new_partition "class", &.class

			Ship.all_ships.each do |ship|
				db[ship.id] = ship
			end

			Ship.all_ships.each do |ship|
				db_ships_by_class.get(ship.class).should contain(ship)
			end

			# We extract the possible classes to do test on them.
			ship_classes = Ship.all_ships.map(&.class).uniq
			ship_classes.each do |klass|
				partition = db_ships_by_class.get klass

				# A partition on “class” should contain entries that all
				# share the same value of “class”.
				partition.map(&.class.==(klass)).reduce { |a, b|
					a && b
				}.should be_true
			end
		end
	end

	describe "tags" do
		it "do basic tagging" do
			db = DODB::SpecDataBase.new

			db_ships_by_tags = db.new_tags "tags", &.tags

			Ship.all_ships.each do |ship|
				db[ship.id] = ship
			end

			db_ships_by_tags.get("flagship").should eq([Ship.flagship])

			# All returned entries should have the requested tag.
			db_ships_by_tags.get("name ship")
				.map(&.tags.includes?("name ship"))
				.reduce { |a, e| a && e }
				.should be_true

			# There shouldn’t be one in our data about WWII Japanese warships…
			db_ships_by_tags.get("starship").should eq([] of Ship)
		end

		it "properly removes tags" do
			db = DODB::SpecDataBase.new

			db_ships_by_tags = db.new_tags "tags", &.tags

			Ship.all_ships.each do |ship|
				db[ship.id] = ship
			end

			# Removing the “flagship” tag, brace for impact.
			flagship = db_ships_by_tags.get("flagship")[0].clone
			flagship.tags = [] of String
			db[flagship.id] = flagship

			db_ships_by_tags.get("flagship").should eq([] of Ship)
		end
	end

	describe "tools" do
		it "rebuilds indexes" do
			db = DODB::SpecDataBase.new

			db_ships_by_name  = db.new_index     "name", &.name
			db_ships_by_class = db.new_partition "class", &.class
			db_ships_by_tags  = db.new_tags      "tags", &.tags

			Ship.all_ships.each do |ship|
				db[ship.id] = ship
			end

			db.reindex_everything!

			Ship.all_ships.each do |ship|
				db_ships_by_name.get?(ship.name).should eq(ship)
				db_ships_by_class.get(ship.class).should contain(ship)
			end
		end

		# Migration testing code will go here as soon as migration testing
		# becomes relevant (due to format changes or so). For small projects,
		# reindexing will work very well in the meantime.
	end
end

