# frozen_string_literal: true

require 'active_support'

module ActiveJsonModel
  module Utils
    def self.recursively_make_indifferent(val)
      return val unless val&.is_a?(Hash) || val&.respond_to?(:map)

      if val.is_a?(Hash)
        val.with_indifferent_access.tap do |w|
          w.each do |k, v|
            w[k] = recursively_make_indifferent(v)
          end
        end
      else
        val.map do |v|
          recursively_make_indifferent(v)
        end
      end
    end
  end
end