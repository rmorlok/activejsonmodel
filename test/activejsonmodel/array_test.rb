# frozen_string_literal: true

require 'json'
require 'base64'

require_relative '../test_helper'

class ArrayTest < Minitest::Test
  class BaseCell
    include ::ActiveJsonModel::Model

    json_attribute :type
    json_attribute :value
    json_polymorphic_via do |data|
      if data[:type] == 'text'
        TextCell
      elsif data[:type] == 'number'
        NumberCell
      else
        BaseCell
      end
    end
  end

  class TextCell < BaseCell
    include ::ActiveJsonModel::Model

    json_fixed_attribute :type, value: 'text'
    json_attribute :value, String
  end

  class NumberCell < BaseCell
    include ::ActiveJsonModel::Model

    json_fixed_attribute :type, value: 'number'
    json_attribute :value, Integer
  end

  class CellArrayOf
    include ::ActiveJsonModel::Array

    json_array_of BaseCell
  end

  def test_array_of_polymorphic_model
    clazz = CellArrayOf

    arr = clazz.new(values: [
      NumberCell.new(value: 1),
      TextCell.new(value: "2"),
      NumberCell.new(value: 3)
    ])

    assert_equal [
                   {type: 'number', value: 1},
                   {type: 'text', value: "2"},
                   {type: 'number', value: 3},
                 ], arr.dump_to_json

    data = ::JSON.dump(clazz.dump(arr))
    h = ::JSON.load(data)
    reconstructed = clazz.load(h)

    assert reconstructed[0].is_a?(NumberCell)
    assert reconstructed[1].is_a?(TextCell)
    assert_equal 3, reconstructed.length
    assert_equal [1, '2', 3], reconstructed.map{|v| v.value}
  end

  class CellArrayPolymorphicBy
    include ::ActiveJsonModel::Array

    json_polymorphic_array_by do |item_data|
      if item_data[:type] == 'text'
        TextCell
      elsif item_data[:type] == 'number'
        NumberCell
      else
        BaseCell
      end
    end
  end

  def test_array_polymorphic_by
    clazz = CellArrayPolymorphicBy

    arr = clazz.new(values: [
      NumberCell.new(value: 1),
      TextCell.new(value: "2"),
      NumberCell.new(value: 3)
    ])

    assert_equal [
                   {type: 'number', value: 1},
                   {type: 'text', value: "2"},
                   {type: 'number', value: 3},
                 ], arr.dump_to_json

    data = ::JSON.dump(clazz.dump(arr))
    h = ::JSON.load(data)
    reconstructed = clazz.load(h)

    assert reconstructed[0].is_a?(NumberCell)
    assert reconstructed[1].is_a?(TextCell)
    assert_equal 3, reconstructed.length
    assert_equal [1, '2', 3], reconstructed.map{|v| v.value}
  end

  class JsonArrayRot13Encrypted
    include ::ActiveJsonModel::Array

    json_array serialize: ->(s){ s.tr("abcdefghijklmnopqrstuvwxyz",
                                      "nopqrstuvwxyzabcdefghijklm") },
               deserialize: ->(s){ s.tr("abcdefghijklmnopqrstuvwxyz",
                                        "nopqrstuvwxyzabcdefghijklm") }
  end

  def test_array_custom_serialization
    clazz = JsonArrayRot13Encrypted

    arr = clazz.new(%w[dog cat mouse])

    assert_equal %w[qbt png zbhfr], arr.dump_to_json

    data = ::JSON.dump(clazz.dump(arr))
    h = ::JSON.load(data)
    reconstructed = clazz.load(h)

    assert_equal 3, reconstructed.length
    assert_equal %w[dog cat mouse], reconstructed.values
  end

  def test_empty_array
    clazz = CellArrayOf

    x = clazz.new

    assert_equal [], x.values

    h = clazz.dump(x)
    assert_equal([], h)

    data = ::JSON.dump(h)
    h = ::JSON.load(data)
    reconstructed = clazz.load(h)

    assert reconstructed
    assert_kind_of clazz, reconstructed
  end

  class ArrayNilStays
    include ::ActiveJsonModel::Array

    json_array_of BaseCell, nil_data_to_empty_array: true
  end

  def test_deserialize_nil
    clazz = ArrayNilStays

    reconstructed = clazz.load(nil)

    assert_equal([], reconstructed.values)
    assert !reconstructed.values_set?

    clazz = CellArrayOf

    reconstructed = clazz.load(nil)

    assert_nil reconstructed

    reconstructed = clazz.new
    reconstructed.load_from_json(nil)
    assert_nil reconstructed.values
    assert !reconstructed.values_set?
  end

  def test_valid_by_default_without_validations
    x = CellArrayOf.new
    assert x.valid?
    assert_empty x.errors

    x << TextCell.new(value: 'foo')
    assert x.valid?
    assert_empty x.errors
    assert_equal 1, x.length
  end

  class CustomValidatorArray
    include ::ActiveJsonModel::Array

    json_array_of BaseCell

    validate :two_elements

    def two_elements
      errors.add(:values, 'Must have exactly 2 elements') unless length == 2
    end
  end

  def test_custom_validation
    x = CustomValidatorArray.new
    assert !x.valid?
    assert_equal 1, x.errors.count

    x << TextCell.new(value: 'foo')
    x << TextCell.new(value: 'bar')
    assert x.valid?
    assert_empty x.errors
  end

  class OneOrTwoCell
    include ::ActiveJsonModel::Model

    json_fixed_attribute :type, value: 'one-or-two'
    json_attribute :value, Integer, validation: {inclusion: {in: 1..2}}
  end

  class RecursiveValidatorArray
    include ::ActiveJsonModel::Array

    json_array_of OneOrTwoCell
  end

  def test_recursive_validation
    x = RecursiveValidatorArray.new
    assert x.valid?
    assert_empty x.errors

    x << OneOrTwoCell.new(value: 1)
    assert x.valid?
    assert_empty x.errors

    x << OneOrTwoCell.new(value: 7)
    assert !x.valid?
    assert_equal 1, x.errors.count
  end

  def test_validates_item_type
    x = RecursiveValidatorArray.new
    assert x.valid?
    assert_empty x.errors

    x << OneOrTwoCell.new(value: 1)
    assert x.valid?
    assert_empty x.errors

    x << TextCell.new(value: 'foo')
    assert !x.valid?
    assert_equal 1, x.errors.count
  end

  class AfterLoad1
    include ::ActiveJsonModel::Array

    attr_accessor :status

    json_array_of OneOrTwoCell

    json_after_load do |obj|
      obj.status = 'loaded'
    end
  end

  class AfterLoad2
    include ::ActiveJsonModel::Array

    attr_accessor :status

    json_array_of OneOrTwoCell

    json_after_load :loaded

    def loaded
      self.status = 'loaded'
    end
  end

  def test_after_load_callback
    clazz = AfterLoad1
    x = clazz.new
    assert_nil x.status
    x = clazz.load([{value: 1}])
    assert_equal 'loaded', x.status

    clazz = AfterLoad2
    x = clazz.new
    assert_nil x.status
    x = clazz.load([{value: 1}])
    assert_equal 'loaded', x.status
  end

  def test_base_invalid_value
    clazz = CellArrayOf

    assert_raises ArgumentError do
      clazz.load(17)
    end

    assert_raises ArgumentError do
      clazz.load({})
    end
  end

  def test_tracking_new
    clazz = CellArrayOf
    assert clazz.new.new?
    assert !clazz.load([{type: 'number', value: 1}]).new?
  end

  def test_tracking_loaded
    clazz = CellArrayOf
    assert !clazz.new.loaded?
    assert clazz.load([{type: 'number', value: 1}]).loaded?
  end

  def test_tracking_dumped
    clazz = CellArrayOf
    assert !clazz.new.dumped?
    assert !clazz.load([{type: 'number', value: 1}]).dumped?

    x = clazz.new
    clazz.dump(x)
    assert x.dumped?

    x = clazz.new
    x.dump_to_json
    assert x.dumped?
  end

  def test_change_tracking_basic
    clazz = CellArrayOf
    x = clazz.new
    assert !x.changed?

    x.values = [{type: 'text', value: 'foo'}]
    assert x.changed?

    x.dump_to_json
    assert !x.changed?

    x.values <<  'bar'
    assert x.changed?
    clazz.dump(x)
    assert !x.changed?

    x = clazz.new(values: [{type: 'text', value: 'foo'}])
    assert !x.changed?

    x = clazz.load([{type: 'text', value: 'foo'}])
    assert !x.changed?

    x = clazz.new
    x.load_from_json([{type: 'text', value: 'foo'}])
    assert !x.changed?
  end

  def test_change_tracking_recursive
    c = NumberCell.new(value: 7)
    x = CellArrayOf.new(values: [c])

    assert !x.changed?

    c.value = 8

    assert x.changed?
  end
end
