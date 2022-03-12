# frozen_string_literal: true

require 'json'

require_relative '../test_helper'

class ModelTest < Minitest::Test
  class FullGenericModelB
    include ::ActiveJsonModel::Model

    json_attribute :foo
  end

  class FullGenericModelA
    include ::ActiveJsonModel::Model

    json_attribute :a_string
    json_attribute :b_string, String
    json_attribute :a_int
    json_attribute :b_int, Integer
    json_attribute :a_datetime
    json_attribute :b_datetime, DateTime
    json_attribute :a_recursive, FullGenericModelB
  end

  def test_generic_roundrip
    original = FullGenericModelA.new(
      a_string: "a_string",
      b_string: "b_string",
      a_int: 1,
      b_int: 2,
      a_datetime: DateTime.new(2022, 11, 13, 11, 17, 59),
      b_datetime: DateTime.new(2021, 11, 13, 11, 17, 59),
      a_recursive: FullGenericModelB.new(foo: 'foo')
    )

    data = ::JSON.dump(FullGenericModelA.dump(original))
    h = ::JSON.load(data)
    reconstructed = FullGenericModelA.load(h)

    assert_equal original.a_string, reconstructed.a_string
    assert_equal original.b_string, reconstructed.b_string
    assert_equal original.a_int, reconstructed.a_int
    assert_equal original.b_int, reconstructed.b_int
    assert_equal original.a_datetime.iso8601, reconstructed.a_datetime
    assert_equal original.b_datetime, reconstructed.b_datetime
    assert_equal original.a_recursive.foo, reconstructed.a_recursive.foo
  end
end
