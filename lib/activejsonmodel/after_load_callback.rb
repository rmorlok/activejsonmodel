# frozen_string_literal: true

module ActiveJsonModel
  class AfterLoadCallback
    attr_reader method_name
    attr_reader block

    # Data holder for an after-load callback
    #
    # @param method_name [Symbol] the name of method to be invoked as a callback
    # @param block [Proc] block to be executed as the callback
    def initialize(method_name:, block:)
      raise "ActiveJsonModel after load callback must either be a block or a method name" if method_name && block
      raise "ActiveJsonModel after load callback must either specify a block or method name" unless method_name || block

      @method_name = method_name.to_sym
      @block = block
    end

    # Invoke this callback on <code>on_object</code> the object just loaded from JSON
    #
    # @param on_object [Object] the object just loaded from JSON
    def invoke(on_object)
      if method_name
        on_object.send(method_name)
      else
        block.call
      end
    end
  end
end