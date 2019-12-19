
abstract class DODB::Indexer(V)
	abstract def index   (key : String, value : V)
	abstract def deindex (key : String, value : V)
	abstract def check!  (key : String, value : V, old_value : V?)
	abstract def name                : String

	abstract def indexing_directory : String
end

