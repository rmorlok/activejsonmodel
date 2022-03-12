# frozen_string_literal: true

require "minitest/reporters"

if ENV["CI"]
  Minitest::Reporters.use!(Minitest::Reporters::SpecReporter.new)
elsif ENV['RM_INFO']
  # Don't define reporters; RubyMine (jetbrains) does this itself.
else
  Minitest::Reporters.use!(Minitest::Reporters::DefaultReporter.new)
end
