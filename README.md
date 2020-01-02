
# dodb.cr

DODB stands for Document Oriented DataBase.

# Installation

Add the following to your `shard.yml`.
You may want to add version informations to avoid unexpected breakages.

```yaml
dependencies:
    dodb:
        git: https://git.karchnu.fr/WeirdOS/dodb.cr
```

# Usage

```crystal
db = DODB::DataBase(Thing).new

db << Thing.new

db.each do |thing|
	pp! thing
end
```

```crystal
# First, we define the thing we’ll want to store.
# It *has* to be serializable through JSON, as everything in DODB is stored in JSON.
class Thing
	include JSON::Serializable

	property id       : String
	property category : String # In this example we’ll assume a unique category.
	property tags     : Array(String)

	def initialize(@id, @category, @tags)
	end
end

# Then we create our database.
things = DODB::DataBase(Thing).new

# Then we define indices to it. There are several ways to index things in DODB.
# Indices are the simplest way to do so. They represent attributes that are
# unique in the collection. They are “1-1” associations.
things_by_id = things.new_index "id", &.id

# Partitions represent attributes that are shared in the collection. They can
# be used to obtain entries grouped by value. They are “1-n” associations.
things_by_category = things.new_partition "category", &.category

# Tags are “n-n associations”.
things_by_tags = things.new_tags "tags", &.tags

# At this point, we can add or try to access data.
things << Thing.new "one",   "word", ["number"] of String
things << Thing.new "two",   "word", ["number"] of String
things << Thing.new "three", "word", ["number"] of String
things << Thing.new "hello, world", "sentence", [] of String

things_by_tags.get? "number" # Will return an array of three things ("one", "two", "three").
things_by_category.get? "sentence" # Will return an array of one thing ("hello, world")
things_by_id.get? "one" # Will return a single thing ("one")

```

