require 'active_model'
require "active_support"

module ActiveJsonModel
  extend ActiveSupport::Autoload

  autoload :VERSION, "active_json_model/version"
  autoload :Model, "active_json_model/model"
  autoload :Array, "active_json_model/array"
  autoload :Utils, "active_json_model/utils"
end
