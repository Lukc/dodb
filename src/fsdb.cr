require "file_utils"
require "json"

require "./fsdb/*"

class DODB::DataBase(K, V)
	@indexers = [] of Indexer(V)

	def initialize(@directory_name : String)
		Dir.mkdir_p data_path
	end

	##
	# name is the name that will be used on the file system.
	def new_partition(name : String, &block : Proc(V, String))
		Partition(V).new(@directory_name, name, block).tap do |table|
			@indexers << table
		end
	end

	##
	# name is the name that will be used on the file system.
	def new_index(name : String, &block : Proc(V, String))
		Index(V).new(@directory_name, name, block).tap do |indexer|
			@indexers << indexer
		end
	end

	def new_tags(name : String, &block : Proc(V, Array(String)))
		Tags(V).new(@directory_name, name, block).tap do |tags|
			@indexers << tags
		end
	end

	def get_index(name : String, key)
		index = @indexers.find &.name.==(name)

		index.not_nil!.as(DODB::Index).get key
	end

	# FIXME: Is this “key” really a K, not just a String?
	def get_partition(table_name : String, partition_name : String)
		partition = @indexers.find &.name.==(table_name)

		partition.not_nil!.as(DODB::Partition).get partition_name
	end

	def get_tags(name, key : K)
		partition = @indexers.find &.name.==(name)

		partition.not_nil!.as(DODB::Tags).get name, key
	end

	def []?(key : K) : V?
		self[key]
	rescue MissingEntry
		# FIXME: Only rescue JSON and “no such file” errors.
		return nil
	end

	def [](key : K) : V
		raise MissingEntry.new(key) unless ::File.exists? file_path key

		read file_path key
	end

	def []=(key : K, value : V)
		old_value = self.[key]?

		check_collisions! key, value, old_value

		# Removes any old indices or partitions pointing to a value about
		# to be replaced.
		if old_value
			remove_partitions key, old_value
		end

		# Avoids corruption in case the application crashes while writing.
		file_path(key).tap do |path|
			::File.write "#{path}.new", value.to_json
			::FileUtils.mv "#{path}.new", path
		end

		write_partitions key, value
	end

	def check_collisions!(key : K, value : V, old_value : V?)
		@indexers.each &.check!(key, value, old_value)
	end

	def write_partitions(key : K, value : V)
		@indexers.each &.index(key, value)
	end

	def delete(key : K)
		value = self[key]?

		return if value.nil?

		begin
			::File.delete file_path key
		rescue
			# FIXME: Only intercept “no such file" errors
		end

		remove_partitions key, value

		value
	end

	def remove_partitions(key : K, value : V)
		@indexers.each &.deindex(key, value)
	end

	##
	# CAUTION: Very slow. Try not to use.
	# Can be useful for making dumps or to restore a database, however.
	def each
		dirname = data_path
		Dir.each_child dirname do |child|
			next if child.match /^\./

			full_path = "#{dirname}/#{child}"

			begin
				# FIXME: Only intercept JSON parsing errors.
				field = read full_path
			rescue
				next
			end

			# FIXME: Will only work for String. :(
			key = child.gsub /\.json$/, ""

			yield key, field
		end
	end

	##
	# CAUTION: Very slow. Try not to use.
	def to_h
		hash = ::Hash(K, V).new

		each do |key, value|
			hash[key] = value
		end

		hash
	end

	private def data_path
		"#{@directory_name}/data"
	end

	private def file_path(key : K)
		"#{data_path}/#{key.to_s}.json"
	end

	private def read(file_path : String)
		V.from_json ::File.read file_path
	end
end

