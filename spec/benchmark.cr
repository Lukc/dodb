require "benchmark"

require "../src/dodb.cr"
require "./test-data.cr"

class DODBCached < DODB::CachedDataBase(Ship)
	def initialize(storage_ext = "", remove_previous_data = true)
		storage_dir = "test-storage#{storage_ext}"

		if remove_previous_data
			::FileUtils.rm_rf storage_dir
		end

		super storage_dir
	end
end

class DODBUnCached < DODB::DataBase(Ship)
	def initialize(storage_ext = "", remove_previous_data = true)
		storage_dir = "test-storage#{storage_ext}"

		if remove_previous_data
			::FileUtils.rm_rf storage_dir
		end

		super storage_dir
	end
end

cached   = DODBCached.new
uncached = DODBUnCached.new

Benchmark.ips do |x|
	x.report("adding values with a cache") do
		Ship.all_ships.each do |ship|
			cached << ship
		end
	end

	x.report("adding values without cache") do
		Ship.all_ships.each do |ship|
			uncached << ship
		end
	end
end

cached   = DODBCached.new
uncached = DODBUnCached.new

Ship.all_ships.each do |ship|
	cached << ship
	uncached << ship
end

Benchmark.ips do |x|
	x.report("to_a with a cache") do
		cached.to_a
	end

	x.report("to_a without cache") do
		uncached.to_a
	end
end

Benchmark.ips do |x|
	x.report("to_h with a cache") do
		cached.to_h
	end

	x.report("to_h without cache") do
		uncached.to_h
	end
end

Benchmark.ips do |x|
	x.report("[0] with a cache") do
		cached[0]
	end

	x.report("[0] without cache") do
		uncached[0]
	end
end
