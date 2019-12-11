
require "file_utils"
require "json"

abstract class FS::Indexer(V)
	abstract def index   (key : String, value : V)
	abstract def deindex (key : String, value : V)
	abstract def check!  (key : String, value : V, old_value : V?)
	abstract def name                : String
end

class FS::Partition(V) < FS::Indexer(V)
	property name         : String
	property key_proc     : Proc(V, String)
	getter   storage_root : String

	def initialize(@storage_root, @name, @key_proc)
		::Dir.mkdir_p get_partition_directory
	end

	def check!(key, value, old_value)
		return true # Partitions don’t have collisions or overloads.
	end

	def index(key, value)
		partition = key_proc.call value

		symlink = get_partition_symlink(partition, key)

		Dir.mkdir_p ::File.dirname symlink

		# FIXME: Should not happen anymore. Should we remove this?
		::File.delete symlink if ::File.exists? symlink

		::File.symlink get_data_symlink(key), symlink
	end

	def deindex(key, value)
		partition = key_proc.call value

		symlink = get_partition_symlink(partition, key)

		::File.delete symlink
	end

	def get(partition)
		r_value = Array(V).new

		partition_directory = get_partition_directory partition
		Dir.each_child partition_directory do |child|
			r_value << V.from_json ::File.read "#{partition_directory}/#{child}"
		end

		r_value
	end

	private def get_partition_directory
		"#{@storage_root}/partitions/by_#{@name}"
	end

	private def get_partition_directory(partition)
		"#{get_partition_directory}/#{partition}"
	end

	private def get_partition_symlink(partition : String, key : String)
		"#{get_partition_directory partition}/#{key}.json"
	end

	private def get_data_symlink(key : String)
		"../../../data/#{key}.json"
	end
end

class FS::Index(V) < FS::Indexer(V)
	property name         : String
	property key_proc     : Proc(V, String)
	getter   storage_root : String

	def initialize(@storage_root, @name, @key_proc)
		Dir.mkdir_p dir_path_indices
	end

	def check!(key, value, old_value)
		index_key = key_proc.call value

		symlink = file_path_index index_key.to_s

		# FIXME: Check it’s not pointing to “old_value”, if any, before raising.
		if ::File.exists? symlink
			if old_value
				old_key = key_proc.call old_value
				return if symlink == file_path_index old_key.to_s
			end

			raise IndexOverload.new "Index '#{@name}' is overloaded for key '#{key}'"
		end
	end

	def index(key, value)
		index_key = key_proc.call value

		symlink = file_path_index index_key

		Dir.mkdir_p ::File.dirname symlink

		# FIXME: Now that this is done in check!, can we remove it?
		if ::File.exists? symlink
			raise Exception.new "symlink already exists: #{symlink}"
		end

		::File.symlink get_data_symlink_index(key), symlink
	end

	def deindex(key, value)
		index_key = key_proc.call value

		symlink = file_path_index index_key

		::File.delete symlink
	end

	def get(index : String) : V?
		V.from_json ::File.read "#{file_path_index index}"
	end

	private def dir_path_indices
		"#{@storage_root}/indices/by_#{@name}"
	end

	private def file_path_index(index_key : String)
		"#{dir_path_indices}/#{index_key}.json"
	end

	private def get_data_symlink_index(key : String)
		"../../data/#{key}.json"
	end
end

class FS::Tags(V) < FS::Indexer(V)
	property name         : String
	property key_proc     : Proc(V, Array(String))
	getter   storage_root : String

	def initialize(@storage_root, @name, @key_proc)
		::Dir.mkdir_p get_tag_directory
	end

	def index(key, value)
		indices = key_proc.call value

		indices.each do |index|
			symlink = get_tagged_entry_path(key.to_s, index)

			Dir.mkdir_p ::File.dirname symlink

			::File.delete symlink if ::File.exists? symlink

			::File.symlink get_data_symlink(key), symlink
		end
	end

	def deindex(key, value)
		indices = key_proc.call value

		indices.each do |index_key|
			symlink = get_tagged_entry_path(key, index_key)

			::File.delete symlink
		end
	end

	def check!(key, value, old_value)
		return true # Tags don’t have collisions or overloads.
	end

	def get(name, key) : Array(V)
		r_value = Array(V).new

		partition_directory = "#{get_tag_directory}/#{key}"

		return r_value unless Dir.exists? partition_directory

		Dir.each_child partition_directory do |child|
			r_value << V.from_json ::File.read "#{partition_directory}/#{child}"
		end

		r_value
	end

	private def get_tag_directory
		"#{@storage_root}/by_tags/by_#{@name}"
	end

	private def get_tagged_entry_path(key : String, index_key : String)
		"#{get_tag_directory}/#{index_key}/#{key}.json"
	end

	private def get_data_symlink(key)
		"../../../data/#{key}.json"
	end
end

class FS::IndexOverload < Exception
end

class FS::Hash(K, V)
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

		index.not_nil!.as(FS::Index).get key
	end

	# FIXME: Is this “key” really a K, not just a String?
	def get_partition(table_name : String, partition_name : String)
		partition = @indexers.find &.name.==(table_name)

		partition.not_nil!.as(FS::Partition).get partition_name
	end

	def get_tags(name, key : K)
		partition = @indexers.find &.name.==(name)

		partition.not_nil!.as(FS::Tags).get name, key
	end

	def []?(key : K) : V?
		begin
			read file_path key
		rescue
			# FIXME: Only rescue JSON and “no such file” errors.
			return nil
		end
	end

	def [](key : K) : V
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

