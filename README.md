
# dodb.cr

DODB stands for Document Oriented DataBase.

## Objective

The objective is to get rid of DBMS when storing simple files directly on the file-system is enough.

## Overview

A brief summary:
- no SQL
- objects are serialized (currently in JSON)
- indexes (simple soft links on the FS) can be created to improve significantly searches in the db

## Limitations

**TODO**: speed tests, elaborate on the matter.

DODB is not compatible with projects:
- having an absolute priority on speed,
  however, DODB is efficient in most cases with the right indexes.
- having relational data


# Installation

Add the following to your `shard.yml`.
You may want to add version informations to avoid unexpected breakages.

```yaml
dependencies:
    dodb:
        git: https://git.karchnu.fr/WeirdOS/dodb.cr
```


# Basic usage

```crystal
# Database creation
db = DODB::DataBase(Thing).new "path/to/storage/directory"

# Adding an element to the db
db << Thing.new

# Reaching all objects in the db
db.each do |thing|
	pp! thing
end
```

# Basic API

## Create the database

The DB creation is simply creating a few directories on the file-system.

```crystal
db = DODB::DataBase(Thing).new "path/to/storage/directory"
```

## Adding a new object

```crystal
db << Thing.new
```

## Sorting the objects

To speed-up searches in the DB, we can sort them, based on their attributes for example.
There are 3 sorting methods:
- index, 1-1 relations, an attribute value is bound to a single object (an identifier)
- partition, 1-n relations, an attribute value may be related to several objects (the color of a car, for instance)
- tags, n-n relations, each object may have several tags, each tag may be related to several objects

Let's take an example.
```Crystal
require "uuid"

class Car
	include JSON::Serializable
	property id    : String
	property color : String

	def initialize(@color)
		@id = UUID.random.to_s
	end
end
```

We want to store `cars` in a database and index them on their `id` attribute:
```Crystal
cars = DODB::DataBase(Car).new "path/to/storage/directory"

# We give a name to the index, then the code to extract the id from a Car instance
cars_by_id = cars.new_index "id", &.id
```

After adding a few objects in the database, here the index in action on the file-system:

```sh
$ tree storage/
storage
├── data
│   ├── 0000000000.json
│   ├── 0000000001.json
│   ├── 0000000002.json
│   ├── 0000000003.json
│   ├── 0000000004.json
│   └── 0000000005.json
├── indices
│   └── by_id
│       ├── 6e109b82-25de-4250-9c67-e7e8415ad5a7.json -> ../../data/0000000003.json
│       ├── 2080131b-97d7-4300-afa9-55b93cdfd124.json -> ../../data/0000000000.json
│       ├── 2118bf1c-e413-4658-b8c1-a08925e20945.json -> ../../data/0000000005.json
│       ├── b53fab8e-f394-49ef-b939-8a670abe278b.json -> ../../data/0000000004.json
│       ├── 7e918680-6bc2-4f29-be7e-3d2e9c8e228c.json -> ../../data/0000000002.json
│       └── 8b4e83e3-ef95-40dc-a6e5-e6e697ce6323.json -> ../../data/0000000001.json
```

We have 5 objects in the DB, each of them have a unique ID attribute, each attribute is related to a single object.
Getting an object by their ID is as simple as `cat storage/indices/by_id/<id>.json`.


Now we want to sort cars based on their `color` attribute.
This time, we use a `partition`, because the relation between the attribute (color) and the object (car) is `1-n`:
```Crystal
cars_by_colors = things.new_partition "color", &.color
```

On the file-system, this translates to:
```sh
$ tree storage/
...
├── partitions
│   └── by_color
│       ├── blue
│       │   ├── 0000000000.json -> ../../../data/0000000000.json
│       │   └── 0000000004.json -> ../../../data/0000000004.json
│       ├── red
│       │   ├── 0000000001.json -> ../../../data/0000000001.json
│       │   ├── 0000000002.json -> ../../../data/0000000002.json
│       │   └── 0000000003.json -> ../../../data/0000000003.json
│       └── violet
│           └── 0000000005.json -> ../../../data/0000000005.json
```

Now the attribute correspond to a directory (blue, red, violet, etc.) containing a symlink for each related object.

Finally, we want to sort cars based on the `keywords` attribute.
This is a n-n relation, each car may have several keywords, each keyword may be related to several cars.
```Crystal
cars_by_keyword = cars.new_tags "keyword", &.keywords
```

On the file-system, this translates to:
```sh
$ tree storage/
...
└── tags
    └── by_keyword
        └── other-tags
            ├── average
            │   ├── data
            │   │   └── 0000000004.json -> ../../../../..//data/0000000004.json
...
            ├── dirty
            │   ├── data
            │   │   └── 0000000005.json -> ../../../../..//data/0000000005.json
...
            ├── elegant
            │   ├── data
            │   │   ├── 0000000000.json -> ../../../../..//data/0000000000.json
            │   │   └── 0000000003.json -> ../../../../..//data/0000000003.json
...
```
This is very similar to partitions, but there is a bit more complexity here since we eventually search for a car matching a combination of keywords.

**TODO**: explanations about our tag-based search and an example.


## Updating an object

In our last example we had a `Car` class, we stored its instances in `cars` and we could identify each instance by its `id` with the index `car_by_id`.
Now, we want to update a car:
```Crystal
# we find a car we want to modify
car = cars_by_id "86a07924-ab3a-4f46-a975-e9803acba22d"

# we modify it
car.color = "Blue"

# update
cars_by_id.update "86a07924-ab3a-4f46-a975-e9803acba22d", car
```

Or, in the case the object may not yet exist:
```Crystal
cars_by_id.update_or_create "86a07924-ab3a-4f46-a975-e9803acba22d", car
```

## Removing an object

```Crystal
cars_by_id.delete "86a07924-ab3a-4f46-a975-e9803acba22d", car

cars_by_class.delete "red"
cars_by_class.delete "red", do |car|
	car.name == "Corvet" || car.keywords.empty
end
```

# Complete example

```Crystal
require "dodb"

# First, we define what we’ll want to store.
# It *has* to be serializable through JSON, everything in DODB is stored in JSON directly on the file-system.
class Car
	include JSON::Serializable

	property name     : String        # unique to each instance (1-1 relations)
	property color    : String        # a simple attribute (1-n relations)
	property keywords : Array(String) # tags about a car, example: "shiny" (n-n relations)

	def initialize(@name, @color, @keywords)
	end
end

#####################
# Database creation #
#####################

cars = DODB::DataBase(Car).new "./bin/storage"


##########################
# Database configuration #
##########################

# There are several ways to index things in DODB.

# We give a name to the index, then the code to extract the name from a Car instance
# (1-1 relations: in this example, names are indexes = they are UNIQUE identifiers)
cars_by_name = cars.new_index "name", &.name

# We want quick searches for cars based on their color
# (1-n relations: a car only has one color, but a color may refer to many cars)
cars_by_color = cars.new_partition "color", &.color

# We also want to search cars on their keywords
# (n-n relations: a car may be described with many keywords and a keyword may be applied to many cars)
cars_by_keyword = cars.new_tags "keyword", &.keywords


##########
# Adding #
##########

cars << Car.new "Corvet",    "red",    [ "shiny", "impressive", "fast", "elegant" ]
cars << Car.new "SUV",       "red",    [ "solid", "impressive" ]
cars << Car.new "Mustang",   "red",    [ "shiny", "impressive", "elegant" ]
cars << Car.new "Bullet-GT", "red",    [ "shiny", "impressive", "fast", "elegant" ]
cars << Car.new "GTI",       "blue",   [ "average" ]
cars << Car.new "Deudeuch",  "violet", [ "dirty", "slow", "only french will understand" ]

# The DB can be accessed as a simple array
cars.each do |car|
	pp! car
end


################
# Searching... #
################

# based on an index (print the only car named "Corvet")
pp! cars_by_name.get "Corvet"

# based on a partition (print all red cars)
pp! cars_by_color.get "red"

# based on a tag
pp! cars_by_keyword.get "fast"



############
# Updating #
############

car = cars_by_name.get "Corvet"
car.color = "blue"
cars_by_name.update "Corvet", car

# we have a car
# and add it to the DB, not knowing in advance if it was already there
car = Car.new "Mustang", "red", [] of String
cars_by_name.update_or_create car.name, car



###############
# Deleting... #
###############

# based on a name
cars_by_name.delete "Deudeuch"

# based on their color
cars_by_color.delete "red"
# based on their color (but not only)
cars_by_color.delete "blue", &.name.==("GTI")

## TAG-based deletion, soon.
# # based on a keyword
# cars_by_keyword.delete "solid"
# # based on a keyword (but not only)
# cars_by_keyword.delete "fast", &.name.==("Corvet")
```
