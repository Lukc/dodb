require "file_utils"
require "json"

require "./dodb/*"

abstract class DODB::Storage(V)
	property directory_name : String

	def initialize(@directory_name : String)
	end

	def request_lock(name, subname = nil)
		r = -1
		file_path = get_lock_file_path name, subname
		file_perms = 0o644

		flags = LibC::O_EXCL | LibC::O_CREAT
		while (r = LibC.open file_path, flags, file_perms) == -1
			sleep 1.milliseconds
		end

		LibC.close r
	end
	def release_lock(name, subname = nil)
		File.delete get_lock_file_path name, subname
	end

	private def index_file
		"#{@directory_name}/last-index"
	end
	def last_index : Int32
		File.read(index_file).to_i
	end
	def last_index=(x : Int32)
		file = File.open(index_file, "w")

		file << x.to_s

		file.close

		x
	rescue
		raise Exception.new "could not update index file"
	end

	def stringify_key(key : Int32)
		# Negative numbers give strange results with Crystal’s printf.
		if key >= 0
			"%010i" % key
		else
			key.to_s
		end
	end

	def <<(item : V)
		request_lock "index"
		index = last_index + 1
		self[index] = item
		self.last_index = index

		release_lock "index"

		index # FIXME: Should we really return the internal key?
	rescue e
		release_lock "index"

		raise e
	end

	def each(reversed : Bool = false, start_offset = 0, end_offset : Int32? = nil)
		each_with_index(
			reversed: reversed,
			start_offset: start_offset,
			end_offset: end_offset
		) do |item, index|
			yield item
		end
	end

	##
	# CAUTION: Very slow. Try not to use.
	def to_a(reversed : Bool = false, start_offset = 0, end_offset : Int32? = nil)
		array = ::Array(V).new

		each(
			reversed: reversed,
			start_offset: start_offset,
			end_offset: end_offset
		) do |value|
			array << value
		end

		array
	end

	##
	# CAUTION: Very slow. Try not to use.
	def to_h(reversed : Bool = false, start_offset = 0, end_offset : Int32? = nil)
		hash = ::Hash(Int32, V).new

		each_with_index(
			reversed: reversed,
			start_offset: start_offset,
			end_offset: end_offset
		) do |element, index|
			hash[index] = element
		end

		hash
	end

	##
	# name is the name that will be used on the file system.
	def new_index(name : String, &block : Proc(V, String))
		Index(V).new(self, @directory_name, name, block).tap do |indexer|
			@indexers << indexer
		end
	end

	def new_nilable_index(name : String, &block : Proc(V, String | DODB::NoIndex))
		Index(V).new(self, @directory_name, name, block).tap do |indexer|
			@indexers << indexer
		end
	end

	def get_index(name : String, key)
		index = @indexers.find &.name.==(name)

		index.not_nil!.as(DODB::Index).get key
	end

	##
	# name is the name that will be used on the file system.
	def new_partition(name : String, &block : Proc(V, String))
		Partition(V).new(self, @directory_name, name, block).tap do |table|
			@indexers << table
		end
	end

	def get_partition(table_name : String, partition_name : String)
		partition = @indexers.find &.name.==(table_name)

		partition.not_nil!.as(DODB::Partition).get partition_name
	end

	def write_partitions(key : Int32, value : V)
		@indexers.each &.index(stringify_key(key), value)
	end

	def new_tags(name : String, &block : Proc(V, Array(String)))
		Tags(V).new(@directory_name, name, block).tap do |tags|
			@indexers << tags
		end
	end

	def get_tags(name, key : String)
		partition = @indexers.find &.name.==(name)

		partition.not_nil!.as(DODB::Tags).get name, key
	end

	def new_directed_graph(name : String, index : DODB::Index(V), &block : Proc(V, Array(String))) : DirectedGraph(V)
		DirectedGraph(V).new(self, @directory_name, index, name, block).tap do |table|
			@indexers << table
		end
	end

	def check_collisions!(key : Int32, value : V, old_value : V?)
		@indexers.each &.check!(stringify_key(key), value, old_value)
	end

	def pop
		request_lock "index"

		index = last_index

		# Some entries may have been removed. We’ll skip over those.
		# Not the most efficient if a large number of indices are empty.
		while index >= 0 && self[index]?.nil?
			index = index - 1
		end

		if index < 0
			return nil
		end

		poped = self[index]

		self.delete index

		last_index = index - 1

		release_lock "index"

		poped
	end

	private def data_path
		"#{@directory_name}/data"
	end

	private def file_path(key : Int32)
		"#{data_path}/%010i.json" % key
	end

	private def locks_directory : String
		"#{@directory_name}/locks"
	end

	private def get_lock_file_path(name : String, subname : String? = nil)
		if subname
			"#{locks_directory}/#{name}-#{subname}.lock" # FIXME: Separator that causes less collisions?
		else
			"#{locks_directory}/#{name}.lock"
		end
	end

	private def read(file_path : String)
		V.from_json ::File.read file_path
	end

	private def remove_data!
		FileUtils.rm_rf data_path
		Dir.mkdir_p data_path
	end

	private def remove_indexing!
		@indexers.each do |indexer|
			FileUtils.rm_rf indexer.indexing_directory
		end
	end

	# A very slow operation that removes all indices and then rewrites
	# them all.
	# FIXME: Is this really useful in its current form? We should remove the
	#        index directories, not the indices based on our current (and
	#        possiblly different from what’s stored) data.
	def reindex_everything!
		old_data = to_h

		remove_indexing!
		remove_data!

		old_data.each do |index, item|
			self[index] = item
		end
	end

	def remove_partitions(key : Int32, value : V)
		@indexers.each &.deindex(stringify_key(key), value)
	end

	def []?(key : Int32) : V?
		self[key]
	rescue MissingEntry
		# FIXME: Only rescue JSON and “no such file” errors.
		return nil
	end

	abstract def [](key : Int32)
	abstract def delete(key : Int32)
end

class DODB::DataBase(V) < DODB::Storage(V)
	@indexers = [] of Indexer(V)

	def initialize(@directory_name : String)
		Dir.mkdir_p data_path
		Dir.mkdir_p locks_directory

		begin
			self.last_index
		rescue
			self.last_index = -1
		end
	end

	def [](key : Int32) : V
		raise MissingEntry.new(key) unless ::File.exists? file_path key

		read file_path key
	end

	def []=(index : Int32, value : V)
		old_value = self.[index]?

		check_collisions! index, value, old_value

		# Removes any old indices or partitions pointing to a value about
		# to be replaced.
		if old_value
			remove_partitions index, old_value
		end

		# Avoids corruption in case the application crashes while writing.
		file_path(index).tap do |path|
			::File.write "#{path}.new", value.to_json
			::FileUtils.mv "#{path}.new", path
		end

		write_partitions index, value

		if index > last_index
			self.last_index = index
		end
	end

	def delete(key : Int32)
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

	private def each_key(reversed = false)
		start = 0
		_end = last_index
		step = 1

		if reversed
			start = _end
			_end = 0
			step = -1
		end

		key = start
		while step == 1 ? key <= _end : key >= _end
			full_path = file_path key

			if File.exists? full_path
				yield key, full_path
			end

			key = key + step
		end
	end

	##
	# CAUTION: Very slow. Try not to use.
	# Can be useful for making dumps or to restore a database, however.
	def each_with_index(reversed : Bool = false, start_offset = 0, end_offset : Int32? = nil)
		dirname = data_path

		offset = -1

		each_key(reversed) do |key, path|
			offset += 1

			if offset < start_offset
				next
			end
			if !end_offset.nil? && offset > end_offset
				next
			end

			begin
				# FIXME: Only intercept JSON parsing errors.
				field = read path
			rescue
				next
			end

			yield field, key
		end
	end
end

require "./cached.cr"
