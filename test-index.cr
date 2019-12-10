require "json"
require "./src/fs.cr"
require "uuid"

# This test basically works if no data is obtained when fetching "broken"
# partitions/indices/tags.

class Ship
	JSON.mapping({
		id: String,
		class: String,
		name: String,
		tags: Array(String)
	})

	def initialize(@name, @class = @name, @tags = [] of String)
		@id = UUID.random.to_s
	end

	getter name
	getter id
end

ships = FS::Hash(String, Ship).new "test-index"
by_name   = ships.new_index        "name", &.name
by_class  = ships.new_partition    "class", &.class
by_id     = ships.new_index        "id",   &.id
by_tags   = ships.new_tags         "tags", &.tags

ship = Ship.new "Mutsuki", "Mutsuki", tags: ["kuchikukan"]
ships[ship.id] = ship

begin
	ship = Ship.new "Mutsuki", "broken", tags: ["kuchikukan"]
	ships[ship.id] = ship
rescue FS::IndexOverload
	puts "rescue: Adding an entry that would overload an index has been prevented."
	# Should happen, ignore it.
else
	puts "ERROR: No IndexOverload exception was raised on index overload."
end

pp! ships.get_index("name").map &.name

