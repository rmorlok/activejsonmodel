require_relative "lib/activejsonmodel/version"

Gem::Specification.new do |spec|
  spec.name = "activejsonmodel"
  spec.version = Activejsonmodel::VERSION
  spec.authors = ["Ryan Morlok"]
  spec.email = ["ryan.morlok@morlok.com"]

  spec.summary = "Active model objects that can be serialized to JSON"
  spec.homepage = "https://github.com/rmorlok/activejsonmodel"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 2.6.0"

  spec.metadata = {
    "bug_tracker_uri" => "https://github.com/rmorlok/activejsonmodel/issues",
    "changelog_uri" => "https://github.com/rmorlok/activejsonmodel/releases",
    "source_code_uri" => "https://github.com/rmorlok/activejsonmodel",
    "homepage_uri" => spec.homepage,
    "rubygems_mfa_required" => "true"
  }

  # Specify which files should be added to the gem when it is released.
  spec.files = Dir.glob(%w[LICENSE.txt README.md {exe,lib}/**/*]).reject { |f| File.directory?(f) }
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]
end
