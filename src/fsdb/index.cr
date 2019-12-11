require "file_utils"
require "json"

require "./indexer.cr"

class FSDB::Index(V) < FSDB::Indexer(V)
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

class FSDB::IndexOverload < Exception
end

