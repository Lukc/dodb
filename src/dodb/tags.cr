require "file_utils"
require "json"

class DODB::Tags(V) < DODB::Indexer(V)
	property name         : String
	property key_proc     : Proc(V, Array(String))
	getter   storage_root : String

	def initialize(@storage_root, @name, @key_proc)
		::Dir.mkdir_p indexing_directory
	end

	# FIXME: The slow is damn too high.
	def tag_combinations(tags)
		combinations = [] of Array(String)

		tags.size.times do |i|
			combinations.concat tags.permutations (i+1)
		end

		return combinations
	end

	def index(key, value)
		indices = key_proc.call(value).sort

		tag_combinations(indices).each do |previous_indices|
			# FIXME: Not on `index`, but on the list of all previous indices.
			symdir = symlinks_directory previous_indices
			otdir  = other_tags_directory previous_indices

			::Dir.mkdir_p symdir
			::Dir.mkdir_p otdir

			symlink = get_tagged_entry_path(key, previous_indices)

			::File.delete symlink if ::File.exists? symlink

			::File.symlink get_data_symlink(key, previous_indices), symlink
		end
	end

	def deindex(key, value)
		indices = key_proc.call(value).sort

		tag_combinations(indices).each do |previous_indices|
			# FIXME: Not on `index`, but on the list of all previous indices.
			symdir = symlinks_directory previous_indices
			otdir  = other_tags_directory previous_indices

			::Dir.mkdir_p symdir
			::Dir.mkdir_p otdir

			symlink = get_tagged_entry_path(key, previous_indices)

			::File.delete symlink if ::File.exists? symlink

			# FIXME: Remove directories if empty?
		end
	end

	def check!(key, value, old_value)
		return true # Tags don’t have collisions or overloads.
	end

	def get_with_indices(key : String) : Array(Tuple(V, Int32))
		get_with_indices [key]
	end

	def get_with_indices(keys : Array(String)) : Array(Tuple(V, Int32))
		r_value = Array(Tuple(V, Int32)).new

		partition_directory = symlinks_directory keys

		return r_value unless Dir.exists? partition_directory

		Dir.each_child partition_directory do |child|
			r_value << {
				V.from_json(::File.read("#{partition_directory}/#{child}")),
				File.basename(child).gsub(/\.json$/, "").to_i
			}
		end

		r_value
	end

	def get(key : String) : Array(V)
		get_with_indices(key).map &.[0]
	end

	def get(keys : Array(String)) : Array(V)
		get_with_indices(keys.sort).map &.[0]
	end

	def indexing_directory : String
		"#{@storage_root}/tags/by_#{@name}"
	end

	private def symlinks_directory(previous_indices : Array(String))
		"#{indexing_directory}#{previous_indices.map { |i| "/other-tags/#{i}" }.join}/data"
	end
	private def other_tags_directory(previous_indices : Array(String))
		"#{indexing_directory}#{previous_indices.map { |i| "/other-tags/#{i}" }.join}/other-tags"
	end

	private def get_tagged_entry_path(key : String, indices : Array(String))
		"#{indexing_directory}#{indices.map { |i| "/other-tags/#{i}" }.join}/data/#{key}.json"
	end
	private def get_data_symlink(key : String, indices : Array(String))
		"../../../#{indices.map { "../../" }.join}/data/#{key}.json"
	end
end

