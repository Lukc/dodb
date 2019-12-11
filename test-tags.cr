require "json"
require "uuid/json"
require "./src/fsdb.cr"

class Article
	JSON.mapping({
		title: String,
		id: String,
		tags: Array(String)
	})
	def initialize(@title, @tags)
		@id = UUID.random.to_s
	end
end

s = FSDB::DataBase(String, Article).new "test-tags"

s.new_tags "tags", &.tags.map(&.downcase)

article = Article.new "Mutsuki", ["mutsuki", "kuchikukan"]
s[article.id] = article

article = Article.new "Kisaragi", ["mutsuki", "kuchikukan"]
s[article.id] = article

article = Article.new "Kongou", ["kongou", "senkan"]
s[article.id] = article

article = Article.new "Haruna", ["kongou", "senkan"]
s[article.id] = article

article = Article.new "Satsuki", ["mutsuki", "kuchikukan"]
s[article.id] = article

article = Article.new "Shiratsuyu", ["shiratsuyu", "kuchikukan"]
s[article.id] = article

article = Article.new "Yuudachi", ["shiratsuyu", "kuchikukan"]
s[article.id] = article

pp! s.get_tags("tags", "senkan").map &.title
pp! s.get_tags("tags", "kuchikukan").map &.title
pp! s.get_tags("tags", "mutsuki").map &.title
pp! s.get_tags("tags", "shiratsuyu").map &.title

s.to_h.size.times do
	first = s.to_h.to_a[0][1]
	puts "Testing removal of the “#{first.title}” item."

	s.delete first.id

	pp! s.get_tags("tags", "senkan").map &.title
	pp! s.get_tags("tags", "kuchikukan").map &.title
	pp! s.get_tags("tags", "mutsuki").map &.title
	pp! s.get_tags("tags", "shiratsuyu").map &.title
end

puts "Testing get_tags on unknown entries."

pp! s.get_tags("tags", "kaga").map &.title

