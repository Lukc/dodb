require "file_utils"
require "json"

class FSDB::Tags(V) < FSDB::Indexer(V)
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

