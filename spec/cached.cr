require "spec"
require "file_utils"

require "../src/dodb.cr"
require "./test-data.cr"


class DODB::SpecDataBase < DODB::CachedDataBase(Ship)
	def initialize(storage_ext = "", remove_previous_data = true)
		storage_dir = "test-storage#{storage_ext}"

		if remove_previous_data
			::FileUtils.rm_rf storage_dir
		end

		super storage_dir
	end
end

describe "DODB::DataBase::Cached" do
	describe "basics" do
		it "store and get data" do
			db = DODB::SpecDataBase.new

			Ship.all_ships.each do |ship|
				db << ship
			end

			db.to_a.sort.should eq(Ship.all_ships.sort)
		end

		it "rewrite already stored data" do
			db = DODB::SpecDataBase.new
			ship = Ship.all_ships[0]

			key = db << ship

			db[key] = Ship.new "broken"
			db[key] = ship

			db[key].should eq(ship)
		end

		it "properly remove data" do
			db = DODB::SpecDataBase.new

			Ship.all_ships.each do |ship|
				db << ship
			end

			Ship.all_ships.each do |ship|
				db.pop
			end

			Ship.all_ships.each_with_index do |ship, i|
				# FIXME: Should it raise a particular exception?
				expect_raises DODB::MissingEntry do
					db[i]
				end

				db[i]?.should be_nil
			end
		end

		it "preserves data on reopening" do
			db1 = DODB::SpecDataBase.new
			db1 << Ship.kisaragi

			db1.to_a.size.should eq(1)

			db2 = DODB::SpecDataBase.new remove_previous_data: false
			db2 << Ship.mutsuki

			# Only difference with DODB::DataBase: for now, concurrent DB cannot coexists.
			db2.to_a.size.should eq(2)
		end

		it "iterates in normal and reversed order" do
			db = DODB::SpecDataBase.new

			Ship.all_ships.each do |ship|
				db << ship
			end

			# The two #each test iteration.
			db.each_with_index do |item, index|
				item.should eq Ship.all_ships[index]
			end

			db.each_with_index(reversed: true) do |item, index|
				item.should eq Ship.all_ships[index]
			end

			# Actual reversal is tested here.
			db.to_a(reversed: true).should eq db.to_a.reverse
		end

		it "respects the provided offsets if any" do
			db = DODB::SpecDataBase.new

			Ship.all_ships.each do |ship|
				db << ship
			end

			db.to_a(start_offset: 0, end_offset: 0)[0]?.should eq Ship.mutsuki
			db.to_a(start_offset: 1, end_offset: 1)[0]?.should eq Ship.kisaragi
			db.to_a(start_offset: 2, end_offset: 2)[0]?.should eq Ship.yayoi

			db.to_a(start_offset: 0, end_offset: 2).should eq [
				Ship.mutsuki, Ship.kisaragi, Ship.yayoi
			]
		end
	end

	describe "indices" do
		it "do basic indexing" do
			db = DODB::SpecDataBase.new

			db_ships_by_name = db.new_index "name", &.name

			Ship.all_ships.each do |ship|
				db << ship
			end

			Ship.all_ships.each_with_index do |ship|
				db_ships_by_name.get?(ship.name).should eq(ship)
			end
		end

		it "raise on index overload" do
			db = DODB::SpecDataBase.new

			db_ships_by_name = db.new_index "name", &.name

			db << Ship.kisaragi

			# Should not be allowed to store an entry whose ???name??? field
			# already exists.
			expect_raises(DODB::IndexOverload) do
				db << Ship.kisaragi
			end
		end

		it "properly deindex" do
			db = DODB::SpecDataBase.new

			db_ships_by_name = db.new_index "name", &.name

			Ship.all_ships.each do |ship|
				db << ship
			end

			Ship.all_ships.each_with_index do |ship, i|
				db.delete i
			end

			Ship.all_ships.each do |ship|
				db_ships_by_name.get?(ship.name).should be_nil
			end
		end

		it "properly reindex" do
			db = DODB::SpecDataBase.new

			db_ships_by_name = db.new_index "name", &.name

			key = db << Ship.kisaragi

			# We give the old id to the new ship, to get it replaced in
			# the database.
			some_new_ship = Ship.all_ships[2].clone

			db[key] = some_new_ship

			db[key].should eq(some_new_ship)

			db_ships_by_name.get?(some_new_ship.name).should eq(some_new_ship)
		end

		it "properly updates" do
			db = DODB::SpecDataBase.new

			db_ships_by_name = db.new_index "name", &.name

			Ship.all_ships.each do |ship|
				db << ship
			end

			new_kisaragi = Ship.kisaragi.clone.tap do |s|
				s.name = "Kisaragi Kai" # Don???t think about it too much.
			end

			# We???re changing an indexed value on purpose.
			db_ships_by_name.update "Kisaragi", new_kisaragi

			db_ships_by_name.get?("Kisaragi").should be_nil
			db_ships_by_name.get?(new_kisaragi.name).should eq new_kisaragi
		end
	end

	describe "partitions" do
		it "do basic partitioning" do
			db = DODB::SpecDataBase.new

			db_ships_by_class = db.new_partition "class", &.klass

			Ship.all_ships.each do |ship|
				db << ship
			end

			Ship.all_ships.each do |ship|
				db_ships_by_class.get(ship.klass).should contain(ship)
			end

			# We extract the possible classes to do test on them.
			ship_classes = Ship.all_ships.map(&.klass).uniq
			ship_classes.each do |klass|
				partition = db_ships_by_class.get klass

				# A partition on ???class??? should contain entries that all
				# share the same value of ???class???.
				partition.map(&.klass.==(klass)).reduce { |a, b|
					a && b
				}.should be_true
			end

			db_ships_by_class.get("does-not-exist").should eq [] of Ship
		end

		it "removes select elements from partitions" do
			db = DODB::SpecDataBase.new

			db_ships_by_class = db.new_partition "class", &.klass

			Ship.all_ships.each do |ship|
				db << ship
			end

			db_ships_by_class.delete "Mutsuki", &.name.==("Kisaragi")

			Ship.all_ships.map(&.klass).uniq.each do |klass|
				partition = db_ships_by_class.get klass

				partition.any?(&.name.==("Kisaragi")).should be_false
			end
		end
	end

	describe "tags" do
		it "do basic tagging" do
			db = DODB::SpecDataBase.new

			db_ships_by_tags = db.new_tags "tags", &.tags

			Ship.all_ships.each do |ship|
				db << ship
			end

			db_ships_by_tags.get("flagship").should eq([Ship.flagship])

			# All returned entries should have the requested tag.
			db_ships_by_tags.get("name ship")
				.map(&.tags.includes?("name ship"))
				.reduce { |a, e| a && e }
				.should be_true

			# There shouldn???t be one in our data about WWII Japanese warships???
			db_ships_by_tags.get("starship").should eq([] of Ship)
		end

		it "properly removes tags" do
			db = DODB::SpecDataBase.new

			db_ships_by_tags = db.new_tags "tags", &.tags

			Ship.all_ships.each do |ship|
				db << ship
			end

			# Removing the ???flagship??? tag, brace for impact.
			flagship, index = db_ships_by_tags.get_with_indices("flagship")[0]
			flagship.tags = [] of String
			db[index] = flagship



#			ship, index = db_ships_by_tags.update(tag: "flagship") do |ship, index|
#				ship.tags = [] of String
#				db[index] = ship
#			end

			db_ships_by_tags.get("flagship").should eq([] of Ship)
		end

		it "gets items that have multiple tags" do
			db = DODB::SpecDataBase.new

			db_ships_by_tags = db.new_tags "tags", &.tags

			Ship.all_ships.each do |ship|
				db << ship
			end

			results = db_ships_by_tags.get(["flagship", "name ship"])
			results.should eq([Ship.yamato])

			results = db_ships_by_tags.get(["name ship", "flagship"])
			results.should eq([Ship.yamato])

			results = db_ships_by_tags.get(["flagship"])
			results.should eq([Ship.yamato])
		end
	end

	describe "atomic operations" do
		it "safe_get and safe_get?" do
			db = DODB::SpecDataBase.new

			db_ships_by_name = db.new_index "name", &.name

			Ship.all_ships.each do |ship|
				db << ship
			end

			Ship.all_ships.each do |ship|
				db_ships_by_name.safe_get ship.name do |results|
					results.should eq(ship)
				end

				db_ships_by_name.safe_get? ship.name do |results|
					results.should eq(ship)
				end
			end
		end
	end

	describe "tools" do
		it "rebuilds indexes" do
			db = DODB::SpecDataBase.new

			db_ships_by_name  = db.new_index     "name", &.name
			db_ships_by_class = db.new_partition "class", &.klass
			db_ships_by_tags  = db.new_tags      "tags", &.tags

			Ship.all_ships.each do |ship|
				db << ship
			end

			db.reindex_everything!

			Ship.all_ships.each do |ship|
				db_ships_by_name.get?(ship.name).should eq(ship)
				db_ships_by_class.get(ship.klass).should contain(ship)
			end
		end

		it "migrates properly" do
			::FileUtils.rm_rf "test-storage-migration-origin"
			old_db = DODB::DataBase(PrimitiveShip).new "test-storage-migration-origin"

			old_ships_by_name  = old_db.new_index     "name", &.name
			old_ships_by_class = old_db.new_partition "class", &.class_name

			PrimitiveShip.all_ships.each do |ship|
				old_db << ship
			end

			# At this point, the ???old??? DB is filled. Now we need to convert
			# to the new DB.

			new_db = DODB::SpecDataBase.new "-migration-target"

			new_ships_by_name  = new_db.new_index     "name", &.name
			new_ships_by_class = new_db.new_partition "class", &.klass
			new_ships_by_tags  = new_db.new_tags      "tags", &.tags

			old_db.each_with_index do |ship, index|
				new_ship = Ship.new ship.name,
					klass: ship.class_name,
					id: ship.id,
					tags: Array(String).new.tap { |tags|
						tags << "name ship" if ship.name == ship.class_name
					}

				new_db[index] = new_ship
			end

			# At this point, the conversion is done, so??? we???re making a few
			# arbitrary tests on the new data.

			old_db.each_with_index do |old_ship, old_index|
				ship = new_db[old_index]

				ship.id.should eq(old_ship.id)
				ship.klass.should eq(old_ship.class_name)

				ship.tags.any?(&.==("name ship")).should be_true if ship.name == ship.klass
			end
		end
	end
end

