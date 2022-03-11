# frozen_string_literal: true

module ActiveJsonModel
  # Instance of an attribute for a model backed by JSON persistence. Data object
  # used for tracking the attributes on the models.
  #
  # e.g.
  #    class class Credentials < ::ActiveJsonModel
  #      json_attribute :username
  #      json_attribute :password
  #    end
  #
  #    #...
  #
  #    # Returns instances of JsonAttribute
  #    Credentials.active_json_model_attributes
  class JsonAttribute
    attr_reader name
    attr_reader clazz
    attr_reader default
    attr_reader validation
    attr_reader block

    # Creates a record of a JSON-backed attribute
    #
    # @param name [Symbol, String] the name of the attribute
    # @param clazz [Class] the Class that implements the type of the attribute (ActiveJsonModel)
    # @param default [Object, ...] the default value for the attribute if unspecified
    # @param validation [Object] an object with properties that represent ActiveModel validation
    # @param block [Object] block to generate a value from the JSON. May take <code>json_value</code> and
    #        <code>json_hash</code>. The raw value and the parent hash being parsed, respectively.
    def initialize(name:, clazz:, default:, validation:, block:)
      @name = name.to_sym
      @clazz = clazz
      @default = default
      @validation = validation
      @block = block
    end

    # Get a default value for this attribute. Handles defaults that can be generators with callbacks and proper
    # cloning of real values to avoid cross-object mutation.
    def get_default_value
      if default
        if default.respond_to?(:call)
          default.call
        else
          default.clone
        end
      end
    end
  end
end