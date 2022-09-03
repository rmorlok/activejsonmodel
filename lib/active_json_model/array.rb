# frozen_string_literal: true

require 'ostruct'

require 'active_support'
require_relative './json_attribute'
require_relative './after_load_callback'

if Gem.find_files("active_record").any?
  require_relative './active_record_type'
  require_relative './active_record_encrypted_type'
end

module ActiveJsonModel
  module Array
    def self.included(base_class)
      # Add all the class methods to the included class
      base_class.extend(ClassMethods)

      # Add additional settings into the class
      base_class.class_eval do
        # Make sure the objects will be ActiveModels
        include ::ActiveModel::Model unless include?(::ActiveModel::Model)

        # This class will be have like a list-like object
        include ::Enumerable unless include?(::Enumerable)

        # Make sure that it has dirty tracking
        include ::ActiveModel::Dirty unless include?(::ActiveModel::Dirty)

        # The raw values for the
        attr_accessor :values

        # Most of the functionality gets delegated to the actual values array. This is almost all possible methods for
        # array, leaving off those that might be problems for equality checking, etc.
        delegate :try_convert, :&, :*, :+, :-, :<<, :<=>, :[], :[]=, :all?, :any?, :append, :assoc, :at, :bsearch,
                 :bsearch_index, :clear, :collect, :collect!, :combination, :compact, :compact!, :concat, :count,
                 :cycle, :deconstruct, :delete, :delete_at, :delete_if, :difference, :dig, :drop, :drop_while,
                 :each, :each_index, :empty?, :eql?, :fetch, :fill, :filter!, :find_index, :first, :flatten,
                 :flatten!, :hash, :include?, :index, :initialize_copy, :insert, :inspect, :intersection, :join,
                 :keep_if, :last, :length, :map, :map!, :max, :min, :minmax, :none?, :old_to_s, :one?, :pack,
                 :permutation, :pop, :prepend, :product, :push, :rassoc, :reject, :reject!, :repeated_combination,
                 :repeated_permutation, :replace, :reverse, :reverse!, :reverse_each, :rindex, :rotate, :rotate!,
                 :sample, :select!, :shift, :shuffle, :shuffle!, :size, :slice, :slice!, :sort, :sort!,
                 :sort_by!, :sum, :take, :take_while, :transpose, :union, :uniq, :uniq!, :unshift, :values_at, :zip, :|,
                 to: :values

        # Has this model changed? Override's <code>ActiveModel::Dirty</code>'s base behavior to properly handle
        # recursive changes.
        #
        # @return [Boolean] true if any attribute has changed, false otherwise
        def changed?
          # Note: this method is implemented here versus in the module overall because if it is implemented in the
          # module overall, it doesn't properly override the implementation for <code>ActiveModel::Dirty</code> that
          # gets dynamically pulled in using the <code>included</code> hook.
          super || values != @_active_json_model_original_values || values&.any?{|val| val&.respond_to?(:changed?) && val.changed? }
        end

        # For new/loaded tracking
        @_active_json_model_dumped = false
        @_active_json_model_loaded = false

        # Register model validation to handle recursive validation into the model tree
        validate :active_json_model_validate

        def initialize(arr=nil, **kwargs)
          if !arr.nil? && !kwargs[:values].nil?
            raise ArgumentError.new('Can only specify either array or values for ActiveJsonModel::Array')
          end

          # Just repackage as named parameters
          kwargs[:values] = arr unless arr.nil?

          unless kwargs.key?(:values)
            kwargs[:values] = []
          end

          # Invoke the superclass constructor to let active model do the work of setting the attributes
          super(**kwargs).tap do |_|
            # Clear out any recorded changes as this object is starting fresh
            clear_changes_information
            @_active_json_model_original_values = self.values
          end
        end

        # Select certain values based on a condition and generate a new ActiveJsonModel Array
        # @return [ActiveJsonModel] the filtered array
        def select(&block)
          if block
            self.class.new(values: values.select(&block))
          else
            values.select
          end
        end

        # As in the real implementation, <code>filter</code> is just <code>select</code>
        alias_method :filter, :select
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

    # Have the values for this array actually be set, or a defaults coming through?
    # @return [Boolean] true if the values have actually been set
    def values_set?
      !!@_active_json_model_values_set
    end

    # Load array for this instance from a JSON array
    #
    # @param json_array [Array] array of data to be loaded into a model instance
    def load_from_json(json_array)
      # Record this object was loaded
      @_active_json_model_loaded = true

      if json_array.nil?
        if self.class.active_json_model_array_serialization_tuple.nil_data_to_empty_array
          self.values = []
        else
          self.values = nil
        end

        @_active_json_model_values_set = false

        return
      end

      if !json_array.respond_to?(:map) || json_array.is_a?(Hash)
        raise ArgumentError.new("Invalid value specified for json_array. Expected array-like object received #{json_array.class}")
      end

      # Record that we have some sort of values set
      @_active_json_model_values_set = true

      # Iterate over all the allowed attributes
      self.values = json_array.map do |json_val|
        if self.class.active_json_model_array_serialization_tuple.deserialize_proc
          self.class.active_json_model_array_serialization_tuple.deserialize_proc.call(json_val)
        else
          send(self.class.active_json_model_array_serialization_tuple.deserialize_method, json_val)
        end
      end

      # Now that the load is complete, mark dirty tracking as clean
      clear_changes_information
      @_active_json_model_original_values = self.values

      # Invoke any on-load callbacks
      self.class.ancestry_active_json_model_load_callbacks.each do |cb|
        cb.invoke(self)
      end
    end

    def dump_to_json
      # Record that the data has been dumped
      @_active_json_model_dumped = true

      unless self.class.active_json_model_array_serialization_tuple
        raise RuntimeError.new('ActiveJsonModel::Array not properly configured')
      end

      return nil if values.nil?

      values.map do |val|
        if self.class.active_json_model_array_serialization_tuple.serialize_proc
          self.class.active_json_model_array_serialization_tuple.serialize_proc.call(val)
        else
          send(self.class.active_json_model_array_serialization_tuple.deserialize_method, val)
        end
      end.tap do |vals|
        # All changes are cleared after dump
        clear_changes_information
        @_active_json_model_original_values = vals
      end
    end

    # Validate method that handles recursive validation into models in the array. Individual validations
    # on attributes for this model will be handled by the standard mechanism.
    def active_json_model_validate
      errors.add(:values, 'ActiveJsonModel::Array values must be an array') unless values.is_a?(::Array)

      values.each_with_index do |val, i|
        # Check if attribute value is an ActiveJsonModel
        if val && val.respond_to?(:valid?)
          # This call to <code>valid?</code> is important because it will actually trigger recursive validations
          unless val.valid?
            val.errors.each do |error|
              errors.add("[#{i}].#{error.attribute}".to_sym, error.message)
            end
          end
        end

        if self.class.active_json_model_array_serialization_tuple.validate_proc

          # It's a proc (likely lambda)
          if self.class.active_json_model_array_serialization_tuple.validate_proc.arity == 4
            # Handle the validator_for_item_type validators that need to take the self as a param
            # for recursive validators
            self.class.active_json_model_array_serialization_tuple.validate_proc.call(val, i, errors, self)
          else
            self.class.active_json_model_array_serialization_tuple.validate_proc.call(val, i, errors)
          end

        elsif self.class.active_json_model_array_serialization_tuple.validate_method

          # It's implemented as method on this object
          send(self.class.active_json_model_array_serialization_tuple.validate_method, val, i)
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
        # Note that this array_data would be stored as jsonb in the database
        def attribute_type
          if Gem.find_files("active_record").any?
            @attribute_type ||= ::ActiveJsonModel::ActiveRecordType.new(self)
          else
            raise RuntimeError.new('ActiveRecord must be installed to use attribute_type')
          end
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
        # Note that this array_data would be stored as a string in the database, encrypted using
        # a symmetric key at the application level.
        def encrypted_attribute_type
          if Gem.find_files("active_record").any?
            if Gem.find_files("symmetric-encryption").any?
              @encrypted_attribute_type ||= ::ActiveJsonModel::ActiveRecordEncryptedType.new(self)
            else
              raise RuntimeError.new('symmetric-encryption must be installed to use attribute_type')
            end
          else
            raise RuntimeError.new('active_record must be installed to use attribute_type')
          end
        end
      end

      # A list of procs that will be executed after array_data has been loaded.
      #
      # @return [Array<Proc>] array of procs executed after array_data is loaded
      def active_json_model_load_callbacks
        @__active_json_model_load_callbacks ||= []
      end

      # A factory defined via <code>json_polymorphic_via</code> that allows the class to choose different concrete
      # classes based on the array_data in the JSON. Property is for only this class, not the entire class hierarchy.
      #
      # @ return [Proc, nil] proc used to select the concrete base class for the list model class
      def active_json_model_polymorphic_factory
        @__active_json_model_polymorphic_factory
      end

      # OpenStruct storing the configuration of of this ActiveJsonModel::Array. Properties include:
      #  serialize_proc - proc used to translate from objects -> json
      #  serialize_method - symbol of method name to call to translate from objects -> json
      #  deserialize_proc - proc used to translate from json -> objects
      #  deserialize_method - symbol of method name to call to translate from json -> objects
      #  keep_nils - boolean flag indicating if nils should be kept in the array after de/serialization
      #  errors_go_to_nil - boolean flag if errors should be capture from the de/serialization methods and translated
      #  to nil
      def active_json_model_array_serialization_tuple
        @__active_json_model_array_serialization_tuple
      end

      # Filter the ancestor hierarchy to those built with <code>ActiveJsonModel::Array</code> concerns
      #
      # @return [Array<Class>] reversed array of classes in the hierarchy of this class that include ActiveJsonModel
      def active_json_model_ancestors
        self.ancestors.filter{|o| o.respond_to?(:active_json_model_array_serialization_tuple)}.reverse
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

      # Configure this list class to have elements of a specific ActiveJsonModel Model type.
      #
      # Example:
      #    class PhoneNumber
      #      include ::ActiveJsonModel::Model
      #
      #      json_attribute :number, String
      #      json_attribute :label, String
      #    end
      #
      #    class PhoneNumberArray
      #      include ::ActiveJsonModel::Array
      #
      #      json_array_of PhoneNumber
      #    end
      #
      # @param clazz [Clazz] the class to use when loading model elements
      # @param validate [Proc, symbol] Proc to use for validating elements of the array. May be a symbol to a method
      #        implemented in the class. Arguments are value, index, errors object (if not method on class). Method
      #        should add items to the errors array if there are errors, Note that if the elements of the array
      #        implement the <code>valid?</code> and <code>errors</code> methods, those are used in addition to the
      #        <code>validate</code> method.
      # @param keep_nils [Boolean] Should the resulting array keep nils? Default is false and the array will be
      #        compacted after deserialization.
      # @param errors_go_to_nil [Boolean] Should excepts be trapped and converted to nil values? Default is true.
      # @param nil_data_to_empty_array [Boolean] When deserializing data, should a nil value make the values array empty
      #        (versus nil values, which will cause errors)
      def json_array_of(clazz, validate: nil, keep_nils: false, errors_go_to_nil: true, nil_data_to_empty_array: false)
        unless clazz && clazz.is_a?(Class)
          raise ArgumentError.new("json_array_of must be passed a class to use as the type for elements of the array. Received '#{clazz}'")
        end

        unless [Integer, Float, String, Symbol, DateTime, Date].any?{|c| c == clazz} || clazz.include?(::ActiveJsonModel::Model)
          raise ArgumentError.new("Class used with json_array_of must include ActiveJsonModel::Model or be of type Integer, Float, String, Symbol, DateTime, or Date")
        end

        if @__active_json_model_array_serialization_tuple
          raise ArgumentError.new("json_array_of, json_polymorphic_array_by, and json_array are exclusive. Exactly one of them must be specified.")
        end

        # Delegate the real work to a serialize/deserialize approach.
        if clazz == Integer
          json_array(serialize: ->(o){ o }, deserialize: ->(d){ d&.to_i },
                     validate: validator_for_item_type(Integer, validate),
                     keep_nils: keep_nils, errors_go_to_nil: errors_go_to_nil,
                     nil_data_to_empty_array: nil_data_to_empty_array)
        elsif clazz == Float
          json_array(serialize: ->(o){ o }, deserialize: ->(d){ d&.to_f },
                     validate: validator_for_item_type(Float, validate),
                     keep_nils: keep_nils, errors_go_to_nil: errors_go_to_nil,
                     nil_data_to_empty_array: nil_data_to_empty_array)
        elsif clazz == String
          json_array(serialize: ->(o){ o }, deserialize: ->(d){ d&.to_s },
                     validate: validator_for_item_type(String, validate),
                     keep_nils: keep_nils, errors_go_to_nil: errors_go_to_nil,
                     nil_data_to_empty_array: nil_data_to_empty_array)
        elsif clazz == Symbol
          json_array(serialize: ->(o){ o&.to_s }, deserialize: ->(d){ d&.to_sym },
                     validate: validator_for_item_type(Symbol, validate),
                     keep_nils: keep_nils, errors_go_to_nil: errors_go_to_nil,
                     nil_data_to_empty_array: nil_data_to_empty_array)
        elsif clazz == DateTime
          json_array(serialize: ->(o){ o&.iso8601 }, deserialize: ->(d){ DateTime.iso8601(d) },
                     validate: validator_for_item_type(DateTime, validate),
                     keep_nils: keep_nils, errors_go_to_nil: errors_go_to_nil,
                     nil_data_to_empty_array: nil_data_to_empty_array)
        elsif clazz == Date
          json_array(serialize: ->(o){ o&.iso8601 }, deserialize: ->(d){ Date.iso8601(d) },
                     validate: validator_for_item_type(Date, validate),
                     keep_nils: keep_nils, errors_go_to_nil: errors_go_to_nil,
                     nil_data_to_empty_array: nil_data_to_empty_array)
        else
          # This is the case where this is a Active JSON Model
          json_array(
            serialize: ->(o) {
              if o && o.respond_to?(:dump_to_json)
                o.dump_to_json
              else
                o
              end
            }, deserialize: ->(d) {
            c = if clazz&.respond_to?(:active_json_model_concrete_class_from_ancestry_polymorphic)
                  clazz.active_json_model_concrete_class_from_ancestry_polymorphic(d) || clazz
                else
                  clazz
                end

            if c
              c.new.tap do |m|
                m.load_from_json(d)
              end
            else
              nil
            end
          },
            validate: validator_for_item_type(clazz, validate),
            keep_nils: keep_nils,
            errors_go_to_nil: errors_go_to_nil,
            nil_data_to_empty_array: nil_data_to_empty_array)
        end
      end

      # The factory for generating instances of the array when hydrating from JSON. The factory must return the
      # ActiveJsonModel::Model implementing class chosen.
      #
      # Example:
      #    class PhoneNumber
      #      include ::ActiveJsonModel::Model
      #
      #      json_attribute :number, String
      #      json_attribute :label, String
      #    end
      #
      #    class Email
      #      include ::ActiveJsonModel::Model
      #
      #      json_attribute :address, String
      #      json_attribute :label, String
      #    end
      #
      #    class ContactInfoArray
      #      include ::ActiveJsonModel::Array
      #
      #      json_polymorphic_array_by do |item_data|
      #        if item_data.key?(:address)
      #          Email
      #        else
      #          PhoneNumber
      #        end
      #      end
      #    end
      # @param factory [Proc, String] that factory method to choose the appropriate class for each element.
      # @param validate [Proc, symbol] Proc to use for validating elements of the array. May be a symbol to a method
      #        implemented in the class. Arguments are value, index, errors object (if not method on class). Method
      #        should add items to the errors array if there are errors, Note that if the elements of the array
      #        implement the <code>valid?</code> and <code>errors</code> methods, those are used in addition to the
      #        <code>validate</code> method.
      # @param keep_nils [Boolean] Should the resulting array keep nils? Default is false and the array will be
      #        compacted after deserialization.
      # @param errors_go_to_nil [Boolean] Should excepts be trapped and converted to nil values? Default is true.
      # @param nil_data_to_empty_array [Boolean] When deserializing data, should a nil value make the values array empty
      #        (versus nil values, which will cause errors)
      def json_polymorphic_array_by(validate: nil, keep_nils: false, errors_go_to_nil: false, nil_data_to_empty_array: false, &factory)
        unless factory && factory.arity == 1
          raise ArgumentError.new("Must pass block taking one argument to json_polymorphic_array_by")
        end

        if @__active_json_model_array_serialization_tuple
          raise ArgumentError.new("json_array_of, json_polymorphic_array_by, and json_array are exclusive. Exactly one of them must be specified.")
        end

        # Delegate the real work to a serialize/deserialize approach.
        json_array(
          serialize: ->(o) {
            if o && o.respond_to?(:dump_to_json)
              o.dump_to_json
            else
              o
            end
          }, deserialize: ->(d) {
          clazz = factory.call(d)

          if clazz&.respond_to?(:active_json_model_concrete_class_from_ancestry_polymorphic)
            clazz = clazz.active_json_model_concrete_class_from_ancestry_polymorphic(d) || clazz
          end

          if clazz
            clazz.new.tap do |m|
              m.load_from_json(d)
            end
          else
            nil
          end
        },
          validate: validate,
          keep_nils: keep_nils,
          errors_go_to_nil: errors_go_to_nil,
          nil_data_to_empty_array: nil_data_to_empty_array)
      end

      # A JSON array that uses arbitrary serialization/deserialization.
      #
      # Example:
      #    class DateTimeArray
      #      include ::ActiveJsonModel::Array
      #
      #      json_array serialize: ->(dt){ dt.iso8601 }
      #               deserialize: ->(s){ DateTime.iso8601(s) }
      #    end
      # @param serialize [Proc, symbol] Proc to use for serialization. May be a symbol to a method implemented
      #        in the class.
      # @param deserialize [Proc, symbol] Proc to use for deserialization. May be a symbol to a method implemented
      #        in the class.
      # @param validate [Proc, symbol] Proc to use for validating elements of the array. May be a symbol to a method
      #        implemented in the class. Arguments are value, index, errors object (if not method on class). Method
      #        should add items to the errors array if there are errors, Note that if the elements of the array
      #        implement the <code>valid?</code> and <code>errors</code> methods, those are used in addition to the
      #        <code>validate</code> method.
      # @param keep_nils [Boolean] Should the resulting array keep nils? Default is false and the array will be
      #        compacted after deserialization.
      # @param errors_go_to_nil [Boolean] Should excepts be trapped and converted to nil values? Default is true.
      # @param nil_data_to_empty_array [Boolean] When deserializing data, should a nil value make the values array empty
      #        (versus nil values, which will cause errors)
      def json_array(serialize:, deserialize:, validate: nil,
                     keep_nils: false, errors_go_to_nil: true, nil_data_to_empty_array: false)
        unless serialize && (serialize.is_a?(Proc) || serialize.is_a?(Symbol))
          raise ArgumentError.new("Must specify serialize to json_array and it must be either a proc or a symbol to refer to a method in the class")
        end

        if serialize.is_a?(Proc) && serialize.arity != 1
          raise ArgumentError.new("Serialize proc must take exactly one argument.")
        end

        unless deserialize && (deserialize.is_a?(Proc) || deserialize.is_a?(Symbol))
          raise ArgumentError.new("Must specify deserialize to json_array and it must be either a proc or a symbol to refer to a method in the class")
        end

        if deserialize.is_a?(Proc) && deserialize.arity != 1
          raise ArgumentError.new("Deserialize proc must take exactly one argument.")
        end

        if @__active_json_model_array_serialization_tuple
          raise ArgumentError.new("json_array_of, json_polymorphic_array_by, and json_array are exclusive. Exactly one of them must be specified.")
        end

        @__active_json_model_array_serialization_tuple = OpenStruct.new.tap do |t|
          if serialize.is_a?(Proc)
            t.serialize_proc = serialize
          else
            t.serialize_method = serialize
          end

          if deserialize.is_a?(Proc)
            t.deserialize_proc = deserialize
          else
            t.deserialize_method = deserialize
          end

          if validate
            if validate.is_a?(Proc)
              t.validate_proc = validate
            else
              t.validate_method = validate
            end
          end

          t.keep_nils = keep_nils
          t.errors_go_to_nil = errors_go_to_nil
          t.nil_data_to_empty_array = nil_data_to_empty_array
        end
      end

      # Crate a validator that can be used to check that items of the array of a specified type.
      #
      # @param clazz [Class] the type to check against
      # @param recursive_validator [Proc, Symbol] an optional validator to be called in addition to this one
      # @return [Proc] a proc to do the validation
      def validator_for_item_type(clazz, recursive_validator=nil)
        ->(val, i, errors, me) do
          unless val&.is_a?(clazz)
            errors.add(:values, "Element #{i} must be of type #{clazz} but is of type #{val&.class}")
          end

          if recursive_validator
            if recursive_validator.is_a?(Proc)
              if recursive_validator.arity == 4
                recursive_validator.call(val, i, errors, me)
              else
                recursive_validator.call(val, i, errors)
              end
            else
              me.send(recursive_validator, val, i)
            end
          end
        end
      end

      # Computes the concrete class that should be used to load the data based on the ancestry tree's
      # <code>json_polymorphic_via</code>. Also handles potential recursion at the leaf nodes of the tree.
      #
      # @param array_data [Array] the array_data being loaded from JSON
      # @return [Class] the class to be used to load the JSON
      def active_json_model_concrete_class_from_ancestry_polymorphic(array_data)
        clazz = nil
        ancestry_active_json_model_polymorphic_factory.each do |proc|
          clazz = proc.call(array_data)
          break if clazz
        end

        if clazz
          if clazz != self && clazz.respond_to?(:active_json_model_concrete_class_from_ancestry_polymorphic)
            clazz.active_json_model_concrete_class_from_ancestry_polymorphic(array_data) || clazz
          else
            clazz
          end
        else
          self
        end
      end

      # Define a polymorphic factory to choose the concrete class for the list model. Note that because the array_data passed
      # to the block is an array of models, you must account for what the behavior is if there are no elements.
      #
      # Example:
      #
      #    class BaseWorkflowArray
      #      include ::ActiveJsonModel::List
      #
      #      json_polymorphic_via do |array_data|
      #        if array_data[0]
      #          if array_data[0][:type] == 'email'
      #            EmailWorkflow
      #          else
      #            WebhookWorkflow
      #          end
      #        else
      #          BaseWorkflowArray
      #        end
      #      end
      #    end
      #
      #    class EmailWorkflow < BaseWorkflow
      #      def home_emails
      #        filter{|e| e.label == 'home'}
      #      end
      #    end
      #
      #    class WebhookWorkflow < BaseWorkflow
      #      def secure_webhooks
      #        filter{|wh| wh.secure }
      #      end
      #    end
      def json_polymorphic_via(&block)
        @__active_json_model_polymorphic_factory = block
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
      # @param json_array_data [String, Array] the data to be loaded into the instance. May be an array or a string.
      # @return Instance of the list class
      def load(json_array_data)
        if json_array_data.nil? || (json_array_data.is_a?(String) && json_array_data.blank?)
          clazz = active_json_model_concrete_class_from_ancestry_polymorphic([])
          if clazz&.active_json_model_array_serialization_tuple&.nil_data_to_empty_array
            return clazz.new.tap do |instance|
              instance.load_from_json(nil)
            end
          else
            return nil
          end
        end

        # Get the array_data to a hash, regardless of the starting array_data type
        array_data = json_array_data.is_a?(String) ? JSON.parse(json_array_data) : json_array_data

        # Recursively make the value have indifferent access
        array_data = ::ActiveJsonModel::Utils.recursively_make_indifferent(array_data)

        # Get the concrete class from the ancestry tree's potential polymorphic behavior. Note this needs to be done
        # for each sub property as well. This just covers the outermost case.
        clazz = active_json_model_concrete_class_from_ancestry_polymorphic(array_data)
        clazz.new.tap do |instance|
          instance.load_from_json(array_data)
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