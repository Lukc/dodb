require "file_utils"
require "json"

require "./exceptions.cr"
require "./indexer.cr"

class DODB::Index(V) < DODB::Indexer(V)
	property name         : String
	property key_proc     : Proc(V, String | NoIndex) | Proc(V, String)
	getter   storage_root : String

	@storage : DODB::Storage(V)

	def initialize(@storage, @storage_root, @name, @key_proc)
		Dir.mkdir_p indexing_directory
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

			raise IndexOverload.new "index '#{@name}' is overloaded for key '#{key}'"
		end
	end

	def index(key, value)
		index_key = key_proc.call value

		return if index_key.is_a? NoIndex

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

		return if index_key.is_a? NoIndex

		symlink = file_path_index index_key

		::File.delete symlink
	end

	def get(index : String) : V
		file_path = file_path_index index

		raise MissingEntry.new(@name, index) unless ::File.exists? file_path

		V.from_json ::File.read file_path
	end

	def get?(index : String) : V?
		get index
	rescue MissingEntry
		nil
	end

	# FIXME: Unlock on exception.
	def safe_get(index : String) : Nil
		@storage.request_lock @name, index
		internal_key = get_key(index).to_s
		@storage.request_lock internal_key

		yield get index

		@storage.release_lock internal_key
		@storage.release_lock @name, index
	end

	def safe_get?(index : String, &block : Proc(V | Nil, Nil)) : Nil
		safe_get index, &block
	rescue MissingEntry
		yield nil
	end

	def get_key(index : String) : Int32
		file_path = file_path_index index

		raise MissingEntry.new(@name, index) unless ::File.exists? file_path

		::File.readlink(file_path)
			.sub(/\.json$/, "")
			.sub(/^.*\//,   "")
			.to_i
	end

	def get_with_key(index : String) : Tuple(V, Int32)
		key = get_key index

		value = @storage[key]

		{value, key}
	end

	# in case new_value hasn't changed its index
	def update(new_value : V)
		index = key_proc.call new_value

		raise Exception.new "new value is not indexable" if index.is_a? NoIndex

		update index, new_value
	end

	def update(index : String, new_value : V)
		_, key = get_with_key index

		@storage[key] = new_value
	end

	def update_or_create(index : String, new_value : V)
		update index, new_value
	rescue MissingEntry
		@storage << new_value
	end

	def delete(index : String)
		key = get_key index

		@storage.delete key
	end

	def indexing_directory : String
		"#{@storage_root}/indices/by_#{@name}"
	end

	# FIXME: Now that it’s being used outside of this class, name it properly.
	def file_path_index(index_key : String)
		"#{indexing_directory}/#{index_key}.json"
	end

	private def get_data_symlink_index(key : String)
		"../../data/#{key}.json"
	end
end

