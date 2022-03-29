# frozen_string_literal: true

require 'active_support'
require_relative './json_attribute'
require_relative './after_load_callback'

if defined?(::ActiveRecord)
  require_relative './active_record_type'
  require_relative './active_record_encrypted_type'
end

module ActiveJsonModel
  module Model
    def self.included(base_class)
      # Add all the class methods to the included class
      base_class.extend(ClassMethods)

      # Add additional settings into the class
      base_class.class_eval do
        # Make sure the objects will be ActiveModels
        include ::ActiveModel::Model unless include?(::ActiveModel::Model)

        # Make sure that it has dirty tracking
        include ::ActiveModel::Dirty unless include?(::ActiveModel::Dirty)

        # Has this model changed? Override's <code>ActiveModel::Dirty</code>'s base behavior to properly handle
        # recursive changes.
        #
        # @return [Boolean] true if any attribute has changed, false otherwise
        def changed?
          # Note: this method is implemented here versus in the module overall because if it is implemented in the
          # module overall, it doesn't properly override the implementation for <code>ActiveModel::Dirty</code> that
          # gets dynamically pulled in using the <code>included</code> hook.
          super || self.class.ancestry_active_json_model_attributes.any? do |attr|
            val = send(attr.name)
            val&.respond_to?(:changed?) && val.changed?
          end
        end

        # For new/loaded tracking
        @_active_json_model_dumped = false
        @_active_json_model_loaded = false

        # Register model validation to handle recursive validation into the model tree
        validate :active_json_model_validate

        def initialize(**kwargs)
          # Apply default values values that weren't specified
          self.class.active_json_model_attributes.filter{|attr| !attr.default.nil?}.each do |attr|
            unless kwargs.key?(attr.name)
              # Set as an instance variable to avoid being recorded as a true set value
              instance_variable_set("@#{attr.name}", attr.get_default_value)

              # Record that the value is a default
              instance_variable_set("@#{attr.name}_is_default", true)
            end
          end

          # You cannot set the fixed JSON attributes by a setter method. Instead, initialize the member variable
          # directly
          self.class.active_json_model_fixed_attributes.each do |k, v|
            instance_variable_set("@#{k}", v)
          end

          # Invoke the superclass constructor to let active model do the work of setting the attributes
          super(**kwargs).tap do |_|
            # Clear out any recorded changes as this object is starting fresh
            clear_changes_information
          end
        end
      end
    end

    # Was this instance loaded from JSON?
    # @return [Boolean] true if loaded from JSON, false otherwise
    def loaded?
      @_active_json_model_loaded
    end

    # Was this instance dumped to JSON?
    # @return [Boolean] true if dumped to JSON, false otherwise
    def dumped?
      @_active_json_model_dumped
    end

    # Is this a new instance that was created without loading, and has yet to be dumped?
    # @return [Boolean] true if new, false otherwise
    def new?
      !loaded? && !dumped?
    end

    # Load data for this instance from a JSON hash
    #
    # @param json_hash [Hash] hash of data to be loaded into a model instance
    def load_from_json(json_hash)
      # Record this object was loaded
      @_active_json_model_loaded = true

      # Cache fixed attributes
      fixed_attributes = self.class.ancestry_active_json_model_fixed_attributes

      # Iterate over all the allowed attributes
      self.class.ancestry_active_json_model_attributes.each do |attr|
        # The value that was set from the hash
        json_value = json_hash[attr.name]

        # Now translate the raw value into how it should interpreted
        if fixed_attributes.key?(attr.name)
          # Doesn't matter what the value was. Must confirm to the fixed value.
          value = fixed_attributes[attr.name]
        elsif !json_hash.key?(attr.name) && attr.default
          # Note that this logic reflects that an explicit nil value is not the same as not set. Only not set
          # generates the default.
          value = attr.get_default_value
        elsif attr.load_proc && json_value
          # Invoke the proc to get a value back. This gives the proc the opportunity to either generate a value
          # concretely or return a class to use.
          value = if attr.load_proc.arity == 2
                    attr.load_proc.call(json_value, json_hash)
                  else
                    attr.load_proc.call(json_value)
                  end

          if value
            # If it's a class, new it up assuming it will support loading from JSON.
            if value.is_a?(Class)
              # First check if it supports polymorphic behavior.
              if value.respond_to?(:active_json_model_concrete_class_from_ancestry_polymorphic)
                value = value.active_json_model_concrete_class_from_ancestry_polymorphic(json_value) || value
              end

              # New up an instance of the class for loading
              value = value.new
            end

            # If supported, recursively allow the model to load from JSON
            if value.respond_to?(:load_from_json)
              value.load_from_json(json_value)
            end
          end
        elsif attr.clazz && json_value
          # Special case certain builtin types
          if Integer == attr.clazz
            value = json_value.to_i
          elsif Float == attr.clazz
            value = json_value.to_f
          elsif String == attr.clazz
            value = json_value.to_s
          elsif Symbol == attr.clazz
            value = json_value.to_sym
          elsif DateTime == attr.clazz
            value = DateTime.iso8601(json_value)
          elsif Date == attr.clazz
            value = Date.iso8601(json_value)
          else
            # First check if it supports polymorphic behavior.
            clazz = if attr.clazz.respond_to?(:active_json_model_concrete_class_from_ancestry_polymorphic)
                      value = attr.clazz.active_json_model_concrete_class_from_ancestry_polymorphic(json_value) || attr.clazz
                    else
                      attr.clazz
                    end

            # New up the instance
            value = clazz.new

            # If supported, recursively allow the model to load from JSON
            if value.respond_to?(:load_from_json)
              value.load_from_json(json_value)
            end
          end
        else
          value = json_value
        end

        # Actually set the value on the instance
        send("#{attr.name}=", value)
      end

      # Now that the load is complete, mark dirty tracking as clean
      clear_changes_information

      # Invoke any on-load callbacks
      self.class.ancestry_active_json_model_load_callbacks.each do |cb|
        cb.invoke(self)
      end
    end

    def dump_to_json
      # Record that the data has been dumped
      @_active_json_model_dumped = true

      # Get the attributes that are constants in the JSON rendering
      fixed_attributes = self.class.ancestry_active_json_model_fixed_attributes

      key_values = []

      self.class.ancestry_active_json_model_attributes.each do |attr|
        # Skip on the off chance of a name collision between normal and fixed attributes
        next if fixed_attributes.key?(attr.name)

        # Don't render the value if it is a default and configured not to
        next unless attr.render_default || !send("#{attr.name}_is_default?")

        # Get the value from the underlying attribute from the instance
        value = send(attr.name)

        # Recurse if the value is itself an ActiveJsonModel
        if value&.respond_to?(:dump_to_json)
          value = value.dump_to_json
        end

        if attr.dump_proc
          # Invoke the proc to do the translation
          value = if attr.dump_proc.arity == 2
                    attr.dump_proc.call(value, self)
                  else
                    attr.dump_proc.call(value)
                  end
        end

        key_values.push([attr.name, value])
      end

      # Iterate over all the allowed attributes (fixed and regular)
      fixed_attributes.each do |key, value|
        # Recurse if the value is itself an ActiveJsonModel (unlikely)
        if value&.respond_to?(:dump_to_json)
          value = value.dump_to_json
        end

        key_values.push([key, value])
      end

      # Render the array of key-value pairs to a hash
      key_values.to_h.tap do |_|
        # All changes are cleared after dump
        clear_changes_information
      end
    end

    # Validate method that handles recursive validation into <code>json_attribute</code>s. Individual validations
    # on attributes for this model will be handled by the standard mechanism.
    def active_json_model_validate
      self.class.active_json_model_attributes.each do |attr|
        val = send(attr.name)

        # Check if attribute value is an ActiveJsonModel
        if val && val.respond_to?(:valid?)
          # This call to <code>valid?</code> is important because it will actually trigger recursive validations
          unless val.valid?
            val.errors.each do |error|
              errors.add("#{attr.name}.#{error.attribute}".to_sym, error.message)
            end
          end
        end
      end
    end

    module ClassMethods
      if defined?(::ActiveRecord)
        # Allow this model to be used as ActiveRecord attribute type in Rails 5+.
        #
        # E.g.
        #    class Credentials < ::ActiveJsonModel; end;
        #
        #    class Integration < ActiveRecord::Base
        #      attribute :credentials, Credentials.attribute_type
        #    end
        #
        # Note that this data would be stored as jsonb in the database
        def attribute_type
          @attribute_type ||= ActiveModelJsonSerializableType.new(self)
        end

        # Allow this model to be used as ActiveRecord attribute type in Rails 5+.
        #
        # E.g.
        #    class SecureCredentials < ::ActiveJsonModel; end;
        #
        #    class Integration < ActiveRecord::Base
        #      attribute :secure_credentials, SecureCredentials.encrypted_attribute_type
        #    end
        #
        # Note that this data would be stored as a string in the database, encrypted using
        # a symmetric key at the application level.
        def encrypted_attribute_type
          @encrypted_attribute_type ||= ActiveModelJsonSerializableEncryptedType.new(self)
        end
      end

      # Attributes that have been defined for this class using <code>json_attribute</code>.
      #
      # @return [Array<JsonAttribute>] Json attributes for this class
      def active_json_model_attributes
        @__active_json_model_attributes ||= []
      end

      # A list of procs that will be executed after data has been loaded.
      #
      # @return [Array<Proc>] array of procs executed after data is loaded
      def active_json_model_load_callbacks
        @__active_json_model_load_callbacks ||= []
      end

      # A factory defined via <code>json_polymorphic_via</code> that allows the class to choose different concrete
      # classes based on the data in the JSON. Property is for only this class, not the entire class hierarchy.
      #
      # @ return [Proc, nil] proc used to select the concrete base class for the model class
      def active_json_model_polymorphic_factory
        @__active_json_model_polymorphic_factory
      end

      # Filter the ancestor hierarchy to those built with <code>ActiveJsonModel::Model</code> concerns
      #
      # @return [Array<Class>] reversed array of classes in the hierarchy of this class that include ActiveJsonModel
      def active_json_model_ancestors
        self.ancestors.filter{|o| o.respond_to?(:active_json_model_attributes)}.reverse
      end

      # Get all active json model attributes for all the class hierarchy tree
      #
      # @return [Array<JsonAttribute>] Json attributes for the ancestry tree
      def ancestry_active_json_model_attributes
        self.active_json_model_ancestors.flat_map(&:active_json_model_attributes)
      end

      # Get all active json model after load callbacks for all the class hierarchy tree
      #
      # @return [Array<AfterLoadCallback>] After load callbacks for the ancestry tree
      def ancestry_active_json_model_load_callbacks
        self.active_json_model_ancestors.flat_map(&:active_json_model_load_callbacks)
      end

      # Get all polymorphic factories in the ancestry chain.
      #
      # @return [Array<Proc>] After load callbacks for the ancestry tree
      def ancestry_active_json_model_polymorphic_factory
        self.active_json_model_ancestors.map(&:active_json_model_polymorphic_factory).filter(&:present?)
      end

      # Get the hash of key-value pairs that are fixed for this class. Fixed attributes render to the JSON payload
      # but cannot be set directly.
      #
      # @return [Hash] set of fixed attributes for this class
      def active_json_model_fixed_attributes
        @__active_json_fixed_attributes ||= {}
      end

      # Get the hash of key-value pairs that are fixed for this class hierarchy. Fixed attributes render to the JSON
      # payload but cannot be set directly.
      #
      # @return [Hash] set of fixed attributes for this class hierarchy
      def ancestry_active_json_model_fixed_attributes
        self
          .active_json_model_ancestors
          .map{|a| a.active_json_model_fixed_attributes}
          .reduce({}, :merge)
      end

      # Set a fixed attribute for the current class. A fixed attribute is a constant value that is set at the class
      # level that still renders to the underlying JSON structure. This is useful when you have a hierarchy of classes
      # which may have certain properties set that differentiate them in the rendered json. E.g. a <code>type</code>
      # attribute.
      #
      # Example:
      #
      #    class BaseWorkflow
      #      include ::ActiveJsonModel::Model
      #      json_attribute :name
      #    end
      #
      #    class EmailWorkflow < BaseWorkflow
      #      include ::ActiveJsonModel::Model
      #      json_fixed_attribute :type, 'email'
      #    end
      #
      #    class WebhookWorkflow < BaseWorkflow
      #      include ::ActiveJsonModel::Model
      #      json_fixed_attribute :type, 'webhook'
      #    end
      #
      #    workflows = [EmailWorkflow.new(name: 'wf1'), WebhookWorkflow.new(name: 'wf2')].map(&:dump_to_json)
      #    # [{"name": "wf1", "type": "email"}, {"name": "wf2", "type": "webhook"}]
      #
      # @param name [Symbol] the name of the attribute
      # @param value [Object] the value to set the attribute to
      def json_fixed_attribute(name, value:)
        active_json_model_fixed_attributes[name.to_sym] = value

        # We could handle fixed attributes as just a get method, but this approach keeps them consistent with the
        # other attributes for things like changed tracking.
        instance_variable_set("@#{name}", value)

        # Define ActiveModel attribute methods (https://api.rubyonrails.org/classes/ActiveModel/AttributeMethods.html)
        # for this class. E.g. reset_<name>
        #
        # Used for dirty tracking for the model.
        #
        # @see https://api.rubyonrails.org/classes/ActiveModel/AttributeMethods/ClassMethods.html#method-i-define_attribute_methods
        define_attribute_methods name

        # Define the getter for this attribute
        attr_reader name

        # Define the setter method to prevent the value from being changed.
        define_method "#{name}=" do |v|
          unless value == v
            raise RuntimeError.new("#{self.class}.#{name} is an Active JSON Model fixed attribute with a value of '#{value}'. It's value cannot be set to '#{v}''.")
          end
        end
      end

      # Define a new attribute for the model that will be backed by a JSON attribute
      #
      # @param name [Symbol, String] the name of the attribute
      # @param clazz [Class] the Class to use to initialize the object type
      # @param default [Object] the default value for the attribute
      # @param render_default [Boolean] should the default value be rendered to JSON? Default is true. Note this only
      #        applies if the value has not be explicitly set. If explicitly set, the value renders, regardless of if
      #        the value is the same as the default value.
      # @param validation [Object] object whose properties correspond to settings for active model validators
      # @param serialize_with [Proc] proc to generate a value from the value to be rendered to JSON. Given
      #        <code>value</code> and <code>parent_model</code> (optional parameter) values. The value returned is
      #        assumed to be a valid JSON value.
      # @param deserialize_with [Proc] proc to deserialize a value from JSON. This is an alternative to passing a block
      #        (<code>load_proc</code>) to the method and has the same semantics.
      # @param load_proc [Proc] proc that allows the model to customize the value generated. The proc is passed
      #        <code>value_json</code> and <code>parent_json</code>. <code>value_json</code> is the value for this
      #        sub-property, and <code>parent_json</code> (optional parameter) is the json for the parent object. This
      #        proc can either return a class or a concrete instance. If a class is returned, a new instance of the
      #        class will be created on JSON load, and if supported, the sub-JSON will be loaded into it. If a concrete
      #        value is returned, it is assumed this is the reconstructed value. This proc allows for simplified
      #        polymorphic load behavior as well as custom deserialization.
      def json_attribute(name, clazz = nil, default: nil, render_default: true, validation: nil,
                         serialize_with: nil, deserialize_with: nil, &load_proc)
        if deserialize_with && load_proc
          raise ArgumentError.new("Cannot specify both deserialize_with and block to json_attribute")
        end

        name = name.to_sym

        # Add the attribute to the collection of json attributes defined for this class
        active_json_model_attributes.push(
          JsonAttribute.new(
            name: name,
            clazz: clazz,
            default: default,
            render_default: render_default,
            validation: validation,
            dump_proc: serialize_with,
            load_proc: load_proc || deserialize_with
          )
        )

        # Define ActiveModel attribute methods (https://api.rubyonrails.org/classes/ActiveModel/AttributeMethods.html)
        # for this class. E.g. reset_<name>
        #
        # Used for dirty tracking for the model.
        #
        # @see https://api.rubyonrails.org/classes/ActiveModel/AttributeMethods/ClassMethods.html#method-i-define_attribute_methods
        define_attribute_methods name

        # Define the getter for this attribute
        attr_reader name

        # Define the setter for this attribute with proper change tracking
        #
        # @param value [...] the value to set the attribute to
        define_method "#{name}=" do |value|
          # Trigger ActiveModle's change tracking system if the value is actually changing
          # @see https://stackoverflow.com/questions/23958170/understanding-attribute-will-change-method
          send("#{name}_will_change!") unless value == instance_variable_get("@#{name}")

          # Set the value as a direct instance variable
          instance_variable_set("@#{name}", value)

          # Record that the value is not a default
          instance_variable_set("@#{name}_is_default", false)
        end

        # Check if the attribute is set to the default value. This implies this value has never been set.
        # @return [Boolean] true if the value has been explicitly set or loaded, false otherwise
        define_method "#{name}_is_default?" do
          !!instance_variable_get("@#{name}_is_default")
        end

        if validation
          validates name, validation
        end
      end

      # Define a polymorphic factory to choose the concrete class for the model.
      #
      # Example:
      #
      #    class BaseWorkflow
      #      include ::ActiveJsonModel::Model
      #
      #      json_polymorphic_via do |data|
      #        if data[:type] == 'email'
      #          EmailWorkflow
      #        else
      #          WebhookWorkflow
      #        end
      #      end
      #    end
      #
      #    class EmailWorkflow < BaseWorkflow
      #      include ::ActiveJsonModel::Model
      #      json_fixed_attribute :type, 'email'
      #    end
      #
      #    class WebhookWorkflow < BaseWorkflow
      #      include ::ActiveJsonModel::Model
      #      json_fixed_attribute :type, 'webhook'
      #    end
      def json_polymorphic_via(&block)
        @__active_json_model_polymorphic_factory = block
      end

      # Computes the concrete class that should be used to load the data based on the ancestry tree's
      # <code>json_polymorphic_via</code>. Also handles potential recursion at the leaf nodes of the tree.
      #
      # @param data [Hash] the data being loaded from JSON
      # @return [Class] the class to be used to load the JSON
      def active_json_model_concrete_class_from_ancestry_polymorphic(data)
        clazz = nil
        ancestry_active_json_model_polymorphic_factory.each do |proc|
          clazz = proc.call(data)
          break if clazz
        end

        if clazz
          if clazz != self && clazz.respond_to?(:active_json_model_concrete_class_from_ancestry_polymorphic)
            clazz.active_json_model_concrete_class_from_ancestry_polymorphic(data) || clazz
          else
            clazz
          end
        else
          self
        end
      end

      # Register a new after load callback which is invoked after the instance is loaded from JSON
      #
      # @param method_name [Symbol, String] the name of the method to be invoked
      # @param block [Proc] block to be executed after load. Will optionally be passed an instance of the loaded object.
      def json_after_load(method_name=nil, &block)
        raise ArgumentError.new("Must specify method or block for ActiveJsonModel after load") unless method_name || block
        raise ArgumentError.new("Can only specify method or block for ActiveJsonModel after load") if method_name && block

        active_json_model_load_callbacks.push(
          AfterLoadCallback.new(
            method_name: method_name,
            block: block
          )
        )
      end

      # Load an instance of the class from JSON
      #
      # @param json_data [String, Hash] the data to be loaded into the instance. May be a hash or a string.
      # @return Instance of the class
      def load(json_data)
        if json_data.nil? || (json_data.is_a?(String) && json_data.blank?)
          return nil
        end

        # Get the data to a hash, regardless of the starting data type
        data = json_data.is_a?(String) ? JSON.parse(json_data) : json_data

        # Recursively make the value have indifferent access
        data = ::ActiveJsonModel::Utils.recursively_make_indifferent(data)

        # Get the concrete class from the ancestry tree's potential polymorphic behavior. Note this needs to be done
        # for each sub property as well. This just covers the outermost case.
        clazz = active_json_model_concrete_class_from_ancestry_polymorphic(data)
        clazz.new.tap do |instance|
          instance.load_from_json(data)
        end
      end

      # Dump the specified object to JSON
      #
      # @param obj [self] object to dump to json
      def dump(obj)
        raise ArgumentError.new("Expected #{self} got #{obj.class} to dump to JSON") unless obj.is_a?(self)
        obj.dump_to_json
      end
    end
  end
end