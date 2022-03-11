# frozen_string_literal: true

module ActiveJsonModel
  # Allows instances of ActiveJsonModels to be serialized JSONB columns for ActiveRecord models.
  #
  #    class Credentials < ::ActiveJsonModel
  #      def self.attribute_type
  #        ActiveRecordType.new(Credentials)
  #      end
  #    end
  #
  #    class Integration < ActiveRecord::Base
  #      attribute :credentials, Credentials.attribute_type
  #    end
  #
  # This is based on:
  # https://jetrockets.pro/blog/rails-5-attributes-api-value-objects-and-jsonb
  class ActiveRecordType < ::ActiveRecord::Type::Value
    include ::ActiveModel::Type::Helpers::Mutable

    # Create an instance bound to a ActiveJsonModel class.
    #
    # e.g.
    #    class Credentials < ::ActiveJsonModel; end
    #    #...
    #    return ActiveRecordType.new(Credentials)
    def initialize(clazz)
      @clazz = clazz
    end

    def type
      :jsonb
    end

    def cast(value)
      if value.is_a?(@clazz)
        value
      elsif value.is_a?(Array)
        @clazz.load(value)
      end
    end

    def deserialize(value)
      if String === value
        decoded = ::ActiveSupport::JSON.decode(value) rescue nil
        @clazz.load(decoded)
      else
        super
      end
    end

    def serialize(value)
      case value
      when @clazz
        ::ActiveSupport::JSON.encode(@clazz.dump(value))
      when Array, Hash
        ::ActiveSupport::JSON.encode(value)
      else
        super
      end
    end

    # Override to handle issues comparing hashes encoded as strings, where the actual order doesn't matter.
    def changed_in_place?(raw_old_value, new_value)
      if raw_old_value.nil? || new_value.nil?
        raw_old_value == new_value
      else
        # Decode is necessary because postgres can change the order of hashes. Round-tripping on the new value side
        # is to handle any dates that might be rendered as strings.
        decoded_raw = ::ActiveSupport::JSON.decode(raw_old_value)
        round_tripped_new = ::ActiveSupport::JSON.decode(new_value.class.dump(new_value))

        decoded_raw != round_tripped_new
      end
    end
  end
end