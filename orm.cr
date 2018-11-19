
require "json"

class FS::Hash(K, V)
	def initialize(@directory_name : String)
		initialize
	end

	def []?(key)
		begin
			read file_path key
		rescue
			# FIXME: Only rescue JSON and “no such file” errors.
			return nil
		end
	end

	def [](key)
		read file_path key
	end

	def []=(key, value)
		File.write file_path(key), value.to_json
	end

	def delete(key)
		value = self[key]?

		begin
			File.delete file_path key
		rescue
			# FIXME: Only intercept “no such file" errors
		end

		value
	end

	def each
		Dir.each_child @directory_name do |child|
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

	private def read(file_path : String)
		V.from_json File.read file_path
	end
end

a = FS::Hash(String, JSON::Any).new "test-storage"

pp! a["a"]
pp! a["no file found"]?
pp! a["invalid json"]?

pp! a["new entry"] = "blip blop"
pp! a.delete "new entry"
pp! a.delete "non-existant entry"

a.each do |k, v|
	pp! k, v
end

