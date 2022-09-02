# encoding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

require "active_json_model/version"

Gem::Specification.new do |spec|
  spec.name = "activejsonmodel"
  spec.version = ActiveJsonModel::VERSION
  spec.authors = ["Ryan Morlok"]
  spec.email = ["ryan.morlok@morlok.com"]

  spec.summary = "Active model objects that can be serialized to JSON"
  spec.description = <<~EOF
A library for creating Active Models that can serialize/deserialize to JSON. This includes full support for validation
and change detection through nested models. You can write polymorphic models or arrays of models and get full support
for natural serialization.

Active JSON Model can optionally be combined with Active Record to create nested child models via JSON/JSONB columns.
EOF

  spec.homepage = "https://github.com/rmorlok/activejsonmodel"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 2.7.0"

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

  spec.add_dependency 'activemodel', '>= 5.1', '< 7.1'
  spec.add_dependency 'activesupport', '>= 5.1', '< 7.1'
end
