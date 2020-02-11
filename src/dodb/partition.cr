require "file_utils"
require "json"

require "./indexer.cr"

class DODB::Partition(V) < DODB::Indexer(V)
	property name         : String
	property key_proc     : Proc(V, String)
	getter   storage_root : String

	@storage : DODB::DataBase(V)

	def initialize(@storage, @storage_root, @name, @key_proc)
		::Dir.mkdir_p indexing_directory
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

		partition_directory = indexing_directory partition

		return r_value unless Dir.exists? partition_directory

		Dir.each_child partition_directory do |child|
			r_value << V.from_json ::File.read "#{partition_directory}/#{child}"
		end

		r_value
	end

	def delete(partition, &matcher)
		partition_directory = indexing_directory partition

		return unless Dir.exists? partition_directory

		Dir.each_child partition_directory do |child|
			path = "#{partition_directory}/#{child}"
			item =  V.from_json ::File.read path

			if yield item
				key = get_key path

				@storage.delete key
			end
		end
	end

	def indexing_directory : String
		"#{@storage_root}/partitions/by_#{@name}"
	end

	private def get_key(path : String) : Int32
		::File.readlink(path)
			.sub(/\.json$/, "")
			.sub(/^.*\//,   "")
			.to_i
	end

	private def indexing_directory(partition)
		"#{indexing_directory}/#{partition}"
	end

	private def get_partition_symlink(partition : String, key : String)
		"#{indexing_directory partition}/#{key}.json"
	end

	private def get_data_symlink(key : String)
		"../../../data/#{key}.json"
	end
end

