require "json"
require "uuid/json"
require "./src/fs.cr"

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

s = FS::Hash(String, Article).new "test-storage-nn"

s.new_nn_partition "tags", &.tags.map(&.downcase)

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

pp! s.get_nn_partition("tags", "senkan").map &.title
pp! s.get_nn_partition("tags", "kuchikukan").map &.title
pp! s.get_nn_partition("tags", "mutsuki").map &.title
pp! s.get_nn_partition("tags", "shiratsuyu").map &.title

s.to_h.size.times do
	first = s.to_h.to_a[0][1]
	puts "Testing removal of the “#{first.title}” item."

	s.delete first.id

	pp! s.get_nn_partition("tags", "senkan").map &.title
	pp! s.get_nn_partition("tags", "kuchikukan").map &.title
	pp! s.get_nn_partition("tags", "mutsuki").map &.title
	pp! s.get_nn_partition("tags", "shiratsuyu").map &.title
end

puts "Testing get_nn_partition on unknown entries."

pp! s.get_nn_partition("tags", "kaga").map &.title

