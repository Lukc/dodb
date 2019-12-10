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

ships = FS::Hash(String, Ship).new "test-edit"
by_name   = ships.new_index        "name", &.name
by_class  = ships.new_partition    "class", &.class
by_id     = ships.new_index        "id",   &.id
by_tags   = ships.new_nn_partition "tags", &.tags

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

no_broken = Array(Array(Ship)).new
puts
puts "Partitions/indices"
pp! ships.get_partition("class", "Mutsuki").map &.name
pp! ships.get_nn_partition("tags", "kuchikukan").map &.name

pp! no_broken << ships.get_partition("class", "broken")
pp! no_broken << ships.get_nn_partition("tags", "broken")

if no_broken.flatten.size > 0
	puts "ERROR: the test failed"
end

