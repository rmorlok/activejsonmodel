# frozen_string_literal: true

require_relative '../test_helper'

class UtilsTest < Minitest::Test
  def test_nil
    assert_nil ::ActiveJsonModel::Utils.recursively_make_indifferent(nil)
  end

  def test_simple_value
    assert_equal 1, ::ActiveJsonModel::Utils.recursively_make_indifferent(1)
  end

  def test_empty_array
    assert_equal [], ::ActiveJsonModel::Utils.recursively_make_indifferent([])
  end

  def test_nested
    data = {
      "foo" => "bar",
      "arr1" => [
        "a",
        "b",
        "c"
      ],
      "arr2" => [
        nil,
        {
          "chi" => "choo"
        }
      ]
    }

    indif = ::ActiveJsonModel::Utils.recursively_make_indifferent(data)

    assert_equal 'bar', indif[:foo]
    assert_equal 'a', indif[:arr1][0]
    assert_nil indif[:arr2][0]
    assert_equal 'choo', indif[:arr2][1][:chi]
  end

  def test_array
    assert_equal 'bar', ::ActiveJsonModel::Utils.recursively_make_indifferent([{ "foo" => "bar"}])[0][:foo]
  end
end
