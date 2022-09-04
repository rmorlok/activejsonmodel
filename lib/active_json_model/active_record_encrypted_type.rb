# frozen_string_literal: true

# Only available if the symmetric-encryption gem is installed
# https://github.com/reidmorrison/symmetric-encryption
if Gem.find_files("symmetric-encryption").any? &&
  Gem.find_files("active_record").any?

  require "symmetric-encryption"
  require 'active_support'
  require_relative './active_record_type'

  module ActiveJsonModel
    # Allows instances of ActiveJsonModels to be serialized JSONB columns for ActiveRecord models.
    #
    #    class Credentials < ::ActiveJsonModel
    #      def self.encrypted_attribute_type
    #        ActiveRecordEncryptedType.new(Credentials)
    #      end
    #    end
    #
    #    class User < ActiveRecord::Base
    #      attribute :credentials, Credentials.encrypted_attribute_type
    #    end
    #
    # Alternatively, the type can be registered ahead of time:
    #
    #    # config/initializers/types.rb
    #    ActiveRecord::Type.register(:credentials_encrypted_type, Credentials.encrypted_attribute_type)
    #
    # Then the custom type can be used as:
    #
    #    class User < ActiveRecord::Base
    #      attribute :credentials, :credentials_encrypted_type
    #    end
    #
    class ActiveRecordEncryptedType < ::ActiveJsonModel::ActiveRecordType
      def type
        :string
      end

      def cast(value)
        @clazz.active_json_model_cast(value)
      end

      def deserialize(value)
        if String === value
            decoded = SymmetricEncryption.decrypt(value, type: :json) rescue nil
          @clazz.load(decoded)
        else
          super
        end
      end

      def serialize(value)
        case value
        when @clazz
          SymmetricEncryption.encrypt(
            @clazz.dump(value),
            random_iv: true,
            type: :json
          )
        when ::Hash, ::HashWithIndifferentAccess, ::Array
          SymmetricEncryption.encrypt(
            value,
            random_iv: true,
            type: :json
          )
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
end