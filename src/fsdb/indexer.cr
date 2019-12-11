
abstract class FSDB::Indexer(V)
	abstract def index   (key : String, value : V)
	abstract def deindex (key : String, value : V)
	abstract def check!  (key : String, value : V, old_value : V?)
	abstract def name                : String
end

