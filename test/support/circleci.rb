# frozen_string_literal: true

# Generate XML test reports that can be parsed by CircleCI
require "minitest/ci" if ENV["CIRCLECI"]
