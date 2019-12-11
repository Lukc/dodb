require "file_utils"
require "json"

require "./indexer.cr"

class DODB::Partition(V) < DODB::Indexer(V)
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

