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
    attr_reader :name
    attr_reader :clazz
    attr_reader :default
    attr_reader :render_default
    attr_reader :validation
    attr_reader :load_proc
    attr_reader :dump_proc

    # Creates a record of a JSON-backed attribute
    #
    # @param name [Symbol, String] the name of the attribute
    # @param clazz [Class] the Class that implements the type of the attribute (ActiveJsonModel)
    # @param default [Object, ...] the default value for the attribute if unspecified
    # @param render_default [Boolean] should the default value be rendered to JSON? Default is true. Note this only
    #        applies if the value has not be explicitly set. If explicitly set, the value renders, regardless of if
    #        the value is the same as the default value.
    # @param validation [Hash] an object with properties that represent ActiveModel validation
    # @param dump_proc [Proc] proc to generate a value from the value to be rendered to JSON. Given <code>value</code>
    #        and <code>parent_model</code> values. The value returned is assumed to be a valid JSON value. The proc
    #        can take either one or two parameters this is automatically handled by the caller.
    # @param load_proc [Proc] proc to generate a value from the JSON. May take <code>json_value</code> and
    #        <code>json_hash</code>. The raw value and the parent hash being parsed, respectively. May return either
    #        a class (which will be instantiated) or a value directly. The proc can take either one or two parameters
    #        this is automatically handled by the caller.
    def initialize(name:, clazz:, default:, render_default: true, validation:, dump_proc:, load_proc:)
      @name = name.to_sym
      @clazz = clazz
      @default = default
      @render_default = render_default
      @validation = validation
      @dump_proc = dump_proc
      @load_proc = load_proc
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