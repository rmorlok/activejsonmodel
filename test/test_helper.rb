# frozen_string_literal: true

require 'simplecov'
SimpleCov.start do
  enable_coverage :branch
  add_filter "/test/"
end

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "activejsonmodel"

require "minitest/autorun"
Dir[File.expand_path("support/**/*.rb", __dir__)].sort.each { |rb| require(rb) }

