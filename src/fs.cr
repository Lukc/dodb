
require "file_utils"
require "json"

class FS::Hash(K, V)
	# Used for 1-n associations.
	class PartitionData(V)
		property name : String
		property key_proc : Proc(V, String)

		def initialize(@name, @key_proc)
		end
	end

	# Used for 1-1 associations.
	class IndexData(V) < PartitionData(V)
	end

	# Used for n-n associations.
	class NNPartitionData(V)
		property name : String
		property key_proc : Proc(V, Array(String))

		def initialize(@name, @key_proc)
		end
	end

	@partitions = [] of PartitionData(V)
	@nn_partitions = [] of NNPartitionData(V)
 
	def initialize(@directory_name : String)
		Dir.mkdir_p data_path
	end

	##
	# name is the name that will be used on the file system.
	def new_partition(name : String, &block : Proc(V, String))
		@partitions.push PartitionData(V).new name, block

		Dir.mkdir_p dir_path_partition(name)
	end

	##
	# name is the name that will be used on the file system.
	def new_index(name : String, &block : Proc(V, String))
		@partitions.push IndexData(V).new name, block

		Dir.mkdir_p dir_path_indexes(name)
	end

	def new_nn_partition(name : String, &block : Proc(V, Array(String)))
		@nn_partitions.push NNPartitionData(V).new name, block

		Dir.mkdir_p "#{@directory_name}/.by_nn_#{name}"
	end

	def get_index(name : String)
		r_value = Array(V).new

		indexes_directory = dir_path_indexes name
		Dir.each_child indexes_directory do |child|
			r_value << V.from_json ::File.read "#{indexes_directory}/#{child}"
		end

		r_value
	end

	def get_partition(name : String, key : K)
		r_value = Array(V).new

		partition_directory = "#{dir_path_partition name}/#{key}"
		Dir.each_child partition_directory do |child|
			r_value << V.from_json ::File.read "#{partition_directory}/#{child}"
		end

		r_value
	end

	def get_nn_partition(name, key : K)
		r_value = Array(V).new

		partition_directory = "#{dir_path_nn name}/#{key}"

		return r_value unless Dir.exists? partition_directory

		Dir.each_child partition_directory do |child|
			r_value << V.from_json ::File.read "#{partition_directory}/#{child}"
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
		# Removes any old indices or partitions pointing to a value about
		# to be replaced.
		self.[key]?.try do |old_value|
			remove_partitions key, old_value
		end

		# Avoids corruption in case the application crashes while writing.
		file_path(key).tap do |path|
			::File.write "#{path}.new", value.to_json
			::FileUtils.mv "#{path}.new", path
		end

		write_partitions key, value
	end

	def write_partitions(key : K, value : V)
		@partitions.each do |index|
			index_key = index.key_proc.call value

			case index
			when IndexData
				symlink = file_path_indexes(key.to_s, index.name)

				Dir.mkdir_p ::File.dirname symlink

				if ::File.exists? symlink
					raise Exception.new "symlink already exists: #{symlink}"
				end

				::File.symlink symlink_path_index(key), symlink
			when PartitionData
				symlink = file_path_partition(key.to_s, index.name, index_key)

				Dir.mkdir_p ::File.dirname symlink

				::File.delete symlink if ::File.exists? symlink

				::File.symlink symlink_path_partition(key), symlink
			end

		end

		@nn_partitions.each do |nn|
			indices = nn.key_proc.call value

			indices.each do |index|
				symlink = file_path_nn(key.to_s, nn.name, index)

				Dir.mkdir_p ::File.dirname symlink

				::File.delete symlink if ::File.exists? symlink

				::File.symlink symlink_path_nn(key), symlink
			end
		end
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
		@partitions.each do |index|
			index_key = index.key_proc.call value

			case index
			when IndexData
				symlink = file_path_indexes(key.to_s, index.name)

				::File.delete symlink
			when PartitionData
				symlink = file_path_partition(key, index.name, index_key)

				::File.delete symlink
			end
		end

		@nn_partitions.each do |nn|
			indices = nn.key_proc.call value

			indices.each do |index_key|
				symlink = file_path_nn(key.to_s, nn.name, index_key)

				::File.delete symlink
			end
		end
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

	private def dir_path_partition(partition_name : String)
		"#{@directory_name}/partitions/by_#{partition_name}"
	end

	private def dir_path_indexes(index_name : String)
		"#{@directory_name}/indexes/by_#{index_name}"
	end

	private def dir_path_nn(name : String)
		"#{@directory_name}/nn_partitions/by_#{name}"
	end

	private def file_path_indexes(key : String, index_name : String)
		"#{dir_path_indexes index_name}/#{key}.json"
	end

	private def file_path_partition(key : String, index_name : String, index_key : String)
		"#{dir_path_partition index_name}/#{index_key}/#{key}.json"
	end

	private def file_path_nn(key : String, index_name : String, index_key : String)
		"#{dir_path_nn index_name}/#{index_key}/#{key}.json"
	end

	private def symlink_path_index(key : K)
		"../../data/#{key.to_s}.json"
	end

	private def symlink_path_partition(key : K)
		"../../../data/#{key.to_s}.json"
	end

	private def symlink_path_nn(key : K)
		symlink_path_partition key
	end

	private def read(file_path : String)
		V.from_json ::File.read file_path
	end
end

