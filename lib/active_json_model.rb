require 'active_model'
require "active_support"

module ActiveJsonModel
  extend ActiveSupport::Autoload

  autoload :VERSION, "activejsonmodel/version"
  autoload :Model, "activejsonmodel/model"
  autoload :Array, "activejsonmodel/array"
  autoload :Utils, "activejsonmodel/utils"
end
