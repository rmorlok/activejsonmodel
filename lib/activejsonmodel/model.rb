# frozen_string_literal: true

require "active_support"

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

        # For new/loaded tracking
        @_active_json_model_dumped = false
        @_active_json_model_loaded = false

        def initialize(**kwargs)
          # Apply default values values that weren't specified
          self.class.ancestry_active_json_model_attributes.filter{|attr| !attr.default.nil?}.each do |attr|
            unless kwargs.key?(attr.name)
              if attr.default
                kwargs[attr.name] = attr.get_default_value
              end
            end
          end

          # Force fixed attributes. These values can't actually be set to different values, so force them
          # to come in as if they were property initialized. This will also override any values that the caller
          # tried to pass in to set these values.
          kwargs.merge!(self.class.ancestry_active_json_model_fixed_attributes)

          # Invoke the superclass constructor to let active model do the work of setting the attributes
          super(**kwargs).tap do |_|
            # Clear out any recorded changes as this object is starting fresh
            clear_changes_information
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

      # Attributes that have been defined for thi class using <code>json_attribute</code>.
      #
      # @return [Array<JsonAttribute>] Json attributes for this class
      def active_json_model_attributes
        @__active_json_model_attributes ||= []
      end

      def active_json_model_load_callbacks
        @__active_json_model_load_callbacks ||= []
      end

      # A factory defined via <code>json_polymorphic_via</code> that allows the class to choose different concrete
      # classes based on the data in the JSON. Property is for only this class, not the entire class hierarchy.
      def active_json_model_polymorphic_factory
        @__active_json_model_polymorphic_factory
      end

      # Filter the ancestor hierarchy to those built with ActiveJsonModel concerns
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

      # Get all polymorphic factories in the ancestory chain.
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
      #      json_attribute :name
      #    end
      #
      #    class EmailWorkflow < BaseWorkflow
      #      json_fixed_attribute :type, 'email'
      #    end
      #
      #    class WebhookWorkflow < BaseWorkflow
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
      end

      # Define a new attribute for the model that will be backed by a JSON attribute
      #
      # @param name [Symbol, String] the name of the attribute
      # @param clazz [Class] the Class to use to initialize the object type
      # @param default [Object] the default value for the attribute
      # @param validation [Object] object whose properties correspond to settings for active model validators
      # @param block [Proc] TODO what does this do?
      def json_attribute(name, clazz = nil, default: nil, validation: nil, &block)
        name = name.to_sym

        # Add the attribute to the collection of json attributes defined for this class
        active_json_model_attributes.push(
          JsonAttribute.new(
            name: name,
            clazz: clazz,
            default: default,
            validation: validation,
            block: block
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
        define_method "#{name}=" do |value|
          # Trigger ActiveModle's change tracking system if the value is actually changing
          # @see https://stackoverflow.com/questions/23958170/understanding-attribute-will-change-method
          send("#{name}_will_change!") unless value == instance_variable_get("@#{name}")

          # Set the value as a direct instance variable
          instance_variable_set("@#{name}", value)
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
      #      json_fixed_attribute :type, 'email'
      #    end
      #
      #    class WebhookWorkflow < BaseWorkflow
      #      json_fixed_attribute :type, 'webhook'
      #    end
      def json_polymorphic_via(&block)
        @__active_json_model_polymorphic_factory = block
      end

      # Register a new after load callback which is invoked after the instance is loaded from JSON
      #
      # @param method_name [Symbol, String] the name of the method to be invoked
      # @param block [Proc] block to be executed after load
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
            value = attr.get_default_value
          elsif attr.block && json_value
            value = attr.block.call(json_value, json_hash)

            # If supported, recursively allow the model to load from JSON
            if value.respond_to?(:load_from_json)
              value.load_from_json(json_value)
            end
          elsif attr.clazz && json_value
            # Special case certain builtin types
            case attr.clazz
            when Integer
              value = json_value.to_i
            when String
              value = json_value.to_s
            when Symbol
              value = json_value.to_sym
            when DateTime
              value = DateTime.iso8601(json_value)
            when Date
              value = Date.iso8601(json_value)
            else
              value = attr.clazz.new

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
        fixed_attributes = self.ancestry_active_json_model_fixed_attributes

        # Iterate over all the allowed attributes
        self.class.ancestry_active_json_model_attributes.each do |attr|

          # If it's a fixed attribute, that constant value is always used
          if fixed_attributes.key?(attr.name)
            # Get the fixed value
            value = fixed_attributes[attr.name]
          else
            # Get the value from the underlying attribute from the instance
            value = send(attr.name)
          end

          # Recurse if the value is itself an ActiveJsonModel
          if value&.respond_to?(:dump_to_json)
            value = value.dump_to_json
          end

          [attr.name, value]
        end.to_h.tap do |_|
          # All changes are cleared after dump
          clear_changes_information
        end
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

        if data.respond_to?(:with_indifferent_access)
          data = data.with_indifferent_access
        end

        #TODO
      end

      # Dump the specified object to JSON
      #
      # @param obj [self] object to dump to json
      def dump(obj)
        raise ArgumentError.new("Expected #{self} got #{obj.class} to dump to JSON") unless obj.is_a?(self)
      end
    end
  end
end