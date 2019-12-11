require "json"
require "./src/fsdb.cr"
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

ships = FSDB::DataBase(String, Ship).new "test-edit"
by_name   = ships.new_index        "name", &.name
by_class  = ships.new_partition    "class", &.class
by_id     = ships.new_index        "id",   &.id
by_tags   = ships.new_tags         "tags", &.tags

ship = Ship.new "Satsuki", "Mutsuki", tags: ["kuchikukan"]
ships[ship.id] = ship

ship = Ship.new "Mutsuki", "Mutsuki", tags: ["kuchikukan"]
ships[ship.id] = ship

ship = Ship.new "Kisaragi", "broken", tags: ["broken"]
kisaragi = ship
ships[ship.id] = ship

ship = Ship.new "Kisaragi", "Mutsuki", tags: ["kuchikukan"]
ship.id = kisaragi.id # Overwriting the “broken” Kisaragi entry.
ships[ship.id] = ship

puts "Database entries"
ships.each do |id, ship|
	p "#{ship.name} (#{ship.class}) [#{ship.tags.join ", "}]"
end

pp! by_class.get("Mutsuki").map(&.name)

no_broken = Array(Array(Ship)).new
puts
puts "Partitions/indices"
pp! ships.get_partition("class", "Mutsuki").map &.name
pp! ships.get_tags("tags", "kuchikukan").map &.name

no_broken << pp! ships.get_partition("class", "broken")
no_broken << pp! ships.get_tags("tags", "broken")

if no_broken.flatten.size > 0
	puts "ERROR: the test failed"
end

##
# Not implemented, will *not* work (or compile).
##

#ships.partition("class", "Mutsuki").get(min: 1, max: 3)
#ships.partition("class", "Mutsuki").get[1]

#ships.partition("class", "Mutsuki").partition("batch", "first").get

#ships.partition("class", "Mutsuki").sorted_by("name").get(min: 0, max: 2)
