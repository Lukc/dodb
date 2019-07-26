require "json"
require "./src/fs.cr"

# Basic mapping testing.

a = FS::Hash(String, JSON::Any).new "test-storage"

a["a"] = JSON::Any.new "now exists"

pp! a["a"]
pp! a["no file found"]?
pp! a["invalid json"]?

pp! a["new entry"] = JSON::Any.new "blip blop"
pp! a.delete "new entry"
pp! a.delete "non-existant entry"

a.each do |k, v|
	pp! k, v
end

# Indexation testing.

require "uuid"

class Article
	JSON.mapping({
		id: String,
		title: String,
		author: String
	})

	def initialize(@id, @title, @author)
	end

	getter author
	getter id
end

articles = FS::Hash(String, Article).new "articles"
by_author = articles.new_partition "author", &.author
by_id = articles.new_index "id", &.id

article = Article.new UUID.random.to_s, "Bleh foo bar", "Satsuki"
articles[article.id] = article

article = Article.new UUID.random.to_s, "Bleh foo bar", "Natsuki"
articles[article.id] = article

article = Article.new UUID.random.to_s, "Bleh foo bar", "Mutsuki"
articles[article.id] = article

articles.delete articles.get_partition("author", "Natsuki")[0].id

article = Article.new UUID.random.to_s, "Bleh foo bar", "Satsuki"
articles[article.id] = article

articles.delete articles.get_partition("author", "Satsuki")[1].id

article = Article.new UUID.random.to_s, "Bleh foo bar", "Satsuki"
articles[article.id] = article

article = Article.new UUID.random.to_s, "Bleh foo bar", "Nagatsuki"
articles[article.id] = article

articles.each do |a, b|
	p a, b
end

