
class FSDB::MissingEntry < Exception
	getter index : String?
	getter key   : String

	def initialize(@index, @key)
		super "no entry in index '#{@index}' for key '#{@key}''"
	end

	def initialize(@key)
		super "no entry for key '#{@key}' in database"
	end
end

class FSDB::IndexOverload < Exception
end
