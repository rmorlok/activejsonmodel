require 'active_model'
require "active_support"

module ActiveJsonModel
  extend ActiveSupport::Autoload

  autoload :ActiveRecordEncryptedType, "active_json_model/active_record_encrypted_type" unless Gem.find_files("active_record").none? || Gem.find_files("symmetric-encryption").none?
  autoload :ActiveRecordType, "active_json_model/active_record_type" unless Gem.find_files("active_record").none?
  autoload :Array, "active_json_model/array"
  autoload :Model, "active_json_model/model"
  autoload :Utils, "active_json_model/utils"
  autoload :VERSION, "active_json_model/version"
end
