require "./depwatcher/*"
require "json"

data = JSON.parse(STDIN)
STDERR.puts data.to_json
source = data["source"]

case type = source["type"].to_s
when "rubygems"
  versions = Depwatcher::Rubygems.check(source["name"].to_s)
when "pypi"
  versions = Depwatcher::Pypi.check(source["name"].to_s)
when "ruby_lang"
  versions = Depwatcher::RubyLang.check
else
  raise "Unkown type: #{source["type"]}"
end

version = data["version"]?
if version
  ref = SemanticVersion.new(version["ref"].to_s) rescue nil
  versions.reject! do |v|
    SemanticVersion.new(v.ref) < ref
  end if ref
end
puts versions.to_json