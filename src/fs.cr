
require "json"

class FS::Hash(K, V)
	class PartitionData(V)
		property name : String
		property key_proc : Proc(V, String)

		def initialize(@name, @key_proc)
		end
	end

	@partitions = [] of PartitionData(V)
 
	def initialize(@directory_name : String)
		Dir.mkdir_p @directory_name
	end

	##
	# name is the name that will be used on the file system.
	def new_partition(name : String, &block : Proc(V, String))
		@partitions.push PartitionData(V).new name, block

		Dir.mkdir_p "#{@directory_name}/.by_#{name}"
	end

	def get_partition(name : String, key : K)
		r_value = Array(V).new

		partition_directory = "#{@directory_name}/.by_#{name}/#{key}"
		Dir.each_child partition_directory do |child|
			pp child

			r_value << V.from_json File.read "#{partition_directory}/#{child}"
		end

		r_value
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
		# FIXME: Update partitions pointing to previous value (in any) 

		File.write file_path(key), value.to_json

		@partitions.each do |index|
			index_key = index.key_proc.call value

			symlink = file_path(key.to_s, index.name, index_key)

			Dir.mkdir_p File.dirname symlink

			File.delete symlink if File.exists? symlink

			File.symlink symlink_path(key), symlink
		end
	end

	def delete(key : K)
		value = self[key]?

		begin
			File.delete file_path key
		rescue
			# FIXME: Only intercept “no such file" errors
		end

		unless value.nil?
			@partitions.each do |index|
				index_key = index.key_proc.call value

				symlink = file_path(key, index.name, index_key)

				puts "old index #{key.to_s} => #{index_key}"
				puts "symlink is #{symlink}"

				File.delete symlink
			end
		end

		value
	end

	##
	# CAUTION: Very slow. Try not to use.
	# Can be useful for making dumps or to restore a database, however.
	def each
		Dir.each_child @directory_name do |child|
			next if child.match /^\./

			full_path = "#{@directory_name}/#{child}"

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

	private def file_path(key : K)
		"#{@directory_name}/#{key.to_s}.json"
	end

	private def file_path(key : String, index_name : String, index_key : String)
		"#{@directory_name}/.by_#{index_name}/#{index_key}/#{key}.json"
	end

	private def symlink_path(key : K)
		"../../#{key.to_s}.json"
	end

	private def read(file_path : String)
		V.from_json File.read file_path
	end
end

