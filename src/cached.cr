require "file_utils"
require "json"

class Hash(K,V)
	def reverse
		rev = Array(Tuple(K,V)).new
		keys = Array(K).new
		each_key do |k|
			keys << k
		end
		keys.reverse.each do |k|
			rev << {k, self.[k]}
		end

		rev
	end
end

class DODB::CachedDataBase(V) < DODB::Storage(V)
	@indexers = [] of Indexer(V)
	property data = Hash(Int32, V).new

	def initialize(@directory_name : String)
		Dir.mkdir_p data_path
		Dir.mkdir_p locks_directory

		begin
			self.last_index
		rescue
			self.last_index = -1
		end

		# TODO: load the database in RAM at start-up
		DODB::DataBase(V).new(@directory_name).each_with_index do |v, index|
			puts "loading value #{v} at index #{index}"
			self[index] = v
		end
	end

	# Getting data from the hash in RAM.
	def []?(key : Int32) : V?
		@data[key]
	rescue e
		# FIXME: rescues any error the same way.
		return nil
	end
	def [](key : Int32) : V
		# raise MissingEntry.new(key) unless ::File.exists? file_path key
		# read file_path key
		@data[key] rescue raise MissingEntry.new(key)
	end

	def []=(index : Int32, value : V)
		old_value = self.[index]?

		check_collisions! index, value, old_value

		# Removes any old indices or partitions pointing to a value about
		# to be replaced.
		if old_value
			remove_partitions index, old_value
		end

		# Avoids corruption in case the application crashes while writing.
		file_path(index).tap do |path|
			::File.write "#{path}.new", value.to_json
			::FileUtils.mv "#{path}.new", path
		end

		write_partitions index, value

		if index > last_index
			self.last_index = index
		end

		@data[index] = value
	end

	##
	# Can be useful for making dumps or to restore a database.
	def each_with_index(reversed : Bool = false, start_offset = 0, end_offset : Int32? = nil)
		i = -1 # do not trust key to be the right index
		(reversed ? @data.reverse : @data).each do |index, v|
			i += 1
			next if start_offset > i
			break unless end_offset.nil? || i <= end_offset

			yield v, index
		end
	end

	def delete(key : Int32)
		value = self[key]?

		return if value.nil?

		begin
			::File.delete file_path key
		rescue
			# FIXME: Only intercept “no such file" errors
		end

		remove_partitions key, value

		@data.delete key
		value
	end

	private def remove_data!
		super
		@data = Hash(Int32, V).new
	end
end
