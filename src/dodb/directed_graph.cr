require "file_utils"
require "json"

require "./indexer.cr"

class DODB::DirectedGraph(V) < DODB::Indexer(V)
	property name         : String
	property key_proc     : Proc(V, Array(String))
	getter   storage_root : String

	getter index : Index(V)

	@storage : DODB::Storage(V)

	def initialize(@storage, @storage_root, @index, @name, @key_proc)
		::Dir.mkdir_p indexing_directory
	end

	def check!(key, value, old_value)
		return true # Graphs don’t have collisions or overloads.
	end

	def index(key, value)
		outgoing_nodes = key_proc.call value
		current_node = @index.key_proc.call value

		# FIXME: Not 100% completely sure what to do with those.
		#        Let’s ignore them for now and assume they’re undefined
		#        behavior.
		return if current_node.is_a? NoIndex

		outgoing_links_directory = get_outgoing_links_directory current_node

		# TODO: Update old incoming links, if any, before removing?
		::FileUtils.rm_r outgoing_links_directory if ::Dir.exists? outgoing_links_directory

		::Dir.mkdir_p outgoing_links_directory

		outgoing_nodes.each do |node|
			outgoing_symlink = get_outgoing_symlink current_node, node
			incoming_symlink = get_incoming_symlink current_node, node

			# FIXME: How necessary is this?
			::File.delete outgoing_symlink if ::File.exists? outgoing_symlink
			::File.delete incoming_symlink if ::File.exists? incoming_symlink

			# Updates outgoing links.
			::File.symlink get_cross_index_data_symlink(node), outgoing_symlink

			# Updates incoming links.
			::Dir.mkdir_p get_incoming_links_directory node
			::File.symlink get_data_symlink(key), incoming_symlink
		end
	end

	def deindex(key, value)
		outgoing_nodes = key_proc.call value
		current_node = @index.key_proc.call value

		::FileUtils.rm_r get_outgoing_links_directory current_node

		outgoing_nodes.each do |node|
			symlink = get_incoming_symlink current_node, node

			::File.delete symlink if ::File.exists? symlink
		end

		::FileUtils.rm_r indexing_directory current_node
	end

	# FIXME: Heavy duplication down below.

	# FIXME: references to missing (eg. removed or never added) nodes will
	#        raise File::NotFoundError. Should be caught and handled.
	def get_incoming_values(node)
		r_value = Array(V).new

		incoming_links_directory = get_incoming_links_directory node

		return r_value unless Dir.exists? incoming_links_directory

		Dir.each_child incoming_links_directory do |child|
			r_value << V.from_json ::File.read "#{incoming_links_directory}/#{child}"
		end

		r_value
	end
	def get_incoming_keys(node)
		r_value = Array(String).new

		incoming_links_directory = get_incoming_links_directory node

		return r_value unless Dir.exists? incoming_links_directory

		Dir.each_child incoming_links_directory do |child|
			r_value << child.sub /.json$/, ""
		end

		r_value
	end

	# FIXME: references to missing (eg. removed or never added) nodes will
	#        raise File::NotFoundError. Should be caught and handled.
	def get_outgoing_values(node)
		r_value = Array(V).new

		outgoing_links_directory = get_outgoing_links_directory node

		return r_value unless Dir.exists? outgoing_links_directory

		Dir.each_child outgoing_links_directory do |child|
			r_value << V.from_json ::File.read "#{outgoing_links_directory}/#{child}"
		end

		r_value
	end
	def get_outgoing_keys(node)
		r_value = Array(String).new

		outgoing_links_directory = get_outgoing_links_directory node

		return r_value unless Dir.exists? outgoing_links_directory

		Dir.each_child outgoing_links_directory do |child|
			r_value << child.sub /.json$/, ""
		end

		r_value
	end

	def indexing_directory : String
		"#{@storage_root}/graphs/by_#{@name}"
	end

	private def get_key(path : String) : Int32
		::File.readlink(path)
			.sub(/\.json$/, "")
			.sub(/^.*\//,   "")
			.to_i
	end

	private def indexing_directory(node)
		"#{indexing_directory}/#{node}"
	end

	private def get_node_symlink(node : String, key : String)
		"#{indexing_directory node}/#{key}.json"
	end

	private def get_outgoing_links_directory(node)
		"#{indexing_directory node}/outgoing"
	end

	private def get_outgoing_symlink(node, link)
		"#{get_outgoing_links_directory node}/#{link}"
	end

	private def get_incoming_links_directory(node)
		"#{indexing_directory node}/incoming"
	end

	private def get_incoming_symlink(node, link)
		"#{get_incoming_links_directory link}/#{node}"
	end

	private def get_data_symlink(key : String)
		"../../../../data/#{key}.json"
	end

	private def get_cross_index_data_symlink(node : String)
		"../../../../../#{@index.file_path_index node}"
	end
end

