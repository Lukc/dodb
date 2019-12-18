require "file_utils"
require "json"

class DODB::Tags(V) < DODB::Indexer(V)
	property name         : String
	property key_proc     : Proc(V, Array(String))
	getter   storage_root : String

	def initialize(@storage_root, @name, @key_proc)
		::Dir.mkdir_p get_tag_directory
	end

	def index(key, value)
		indices = key_proc.call value

		indices.each do |index|
			symlink = get_tagged_entry_path(key, index)

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

	def get_with_indices(key) : Array(Tuple(V, Int32))
		r_value = Array(Tuple(V, Int32)).new

		partition_directory = "#{get_tag_directory}/#{key}"

		return r_value unless Dir.exists? partition_directory

		Dir.each_child partition_directory do |child|
			r_value << {
				V.from_json(::File.read("#{partition_directory}/#{child}")),
				File.basename(child).gsub(/\.json$/, "").to_i
			}
		end

		r_value
	end

	def get(key) : Array(V)
		get_with_indices(key).map &.[0]
	end

	private def get_tag_directory
		"#{@storage_root}/by_tags/by_#{@name}"
	end

	private def get_tagged_entry_path(key : String, index_key : String)
		"#{get_tag_directory}/#{index_key}/#{key}.json"
	end

	private def get_data_symlink(key : String)
		"../../../data/#{key}.json"
	end
end

