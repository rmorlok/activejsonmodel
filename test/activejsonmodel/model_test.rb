# frozen_string_literal: true

require 'json'

require_relative '../test_helper'

class ModelTest < Minitest::Test
  class NoAttributes
    include ::ActiveJsonModel::Model
  end

  def test_no_attributes
    clazz = NoAttributes

    x = clazz.new

    h = clazz.dump(x)
    assert_equal({}, h)

    data = ::JSON.dump(h)
    h = ::JSON.load(data)
    reconstructed = clazz.load(h)

    assert reconstructed
    assert_kind_of clazz, reconstructed
  end

  class SingleAttribute
    include ::ActiveJsonModel::Model

    json_attribute :foo
  end

  def test_single_attribute_populated
    clazz = SingleAttribute

    x = clazz.new(foo: 'bar')

    h = clazz.dump(x)
    assert_equal({foo: 'bar'}, h)

    data = ::JSON.dump(h)
    h = ::JSON.load(data)
    reconstructed = clazz.load(h)

    assert_equal 'bar', reconstructed.foo
  end

  def test_single_attribute_nil
    clazz = SingleAttribute

    x = clazz.new

    h = clazz.dump(x)
    assert_equal({foo: nil}, h)

    data = ::JSON.dump(h)
    h = ::JSON.load(data)
    reconstructed = clazz.load(h)

    assert_nil reconstructed.foo
  end

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
    json_attribute :a_date
    json_attribute :b_date, Date
    json_attribute :a_symbol, Symbol
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
      a_date: Date.new(2020, 3, 1),
      b_date: Date.new(2021, 4, 1),
      a_symbol: :a_symbol,
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
    assert_equal original.a_date.iso8601, reconstructed.a_date
    assert_equal original.b_date, reconstructed.b_date
    assert_equal original.a_symbol, reconstructed.a_symbol
    assert_equal original.a_recursive.foo, reconstructed.a_recursive.foo
  end

  class DefaultFromConstant
    include ::ActiveJsonModel::Model

    json_attribute :name, default: 'Bob Dole'
  end

  def test_sets_default_from_constant
    x = DefaultFromConstant.new

    assert_equal 'Bob Dole', x.name
    assert_equal({name: 'Bob Dole'}, x.dump_to_json)
  end

  class DefaultFromCallable
    include ::ActiveJsonModel::Model

    json_attribute :name, default: -> {'Bob Dole'}
  end

  def test_sets_default_from_callable
    x = DefaultFromCallable.new

    assert_equal 'Bob Dole', x.name
    assert_equal({name: 'Bob Dole'}, x.dump_to_json)
  end

  def test_allows_default_to_be_overridden_on_construction
    x = DefaultFromConstant.new(name: 'Jimmy Carter')

    assert_equal 'Jimmy Carter', x.name
    assert_equal({name: 'Jimmy Carter'}, x.dump_to_json)

    y = DefaultFromCallable.new(name: 'Jimmy Carter')

    assert_equal 'Jimmy Carter', y.name
    assert_equal({name: 'Jimmy Carter'}, y.dump_to_json)
  end

  class SimpleAdditiveInheritanceParent
    include ::ActiveJsonModel::Model

    json_attribute :parent
  end

  class SimpleAdditiveInheritanceChild < SimpleAdditiveInheritanceParent
    include ::ActiveJsonModel::Model

    json_attribute :child
  end

  def test_simple_additive_inheritence
    x = SimpleAdditiveInheritanceChild.new(parent: 'x', child: 'y')

    assert_equal({parent: 'x', child: 'y'}, x.dump_to_json)

    data = ::JSON.dump(SimpleAdditiveInheritanceChild.dump(x))
    h = ::JSON.load(data)
    reconstructed = SimpleAdditiveInheritanceChild.load(h)

    assert_equal'x',  reconstructed.parent
    assert_equal 'y', reconstructed.child
    assert_equal SimpleAdditiveInheritanceChild, reconstructed.class
  end

  def test_dump_rejects_wrong_class
    assert_raises(ArgumentError) do
      SimpleAdditiveInheritanceChild.dump(DefaultFromConstant.new)
    end
  end

  def test_valid_by_default_without_validations
    x = DefaultFromConstant.new
    assert x.valid?
    assert_empty x.errors
  end

  class RangeValidator
    include ::ActiveJsonModel::Model

    json_attribute :stars, Integer, validation: {inclusion: {in: 1..5}}
  end

  def test_validations
    x = RangeValidator.new(stars: 3)

    assert x.valid?
    assert_empty x.errors

    x.stars = 6

    assert !x.valid?
    assert_equal 1, x.errors.count
  end

  class ValidateParent
    include ::ActiveJsonModel::Model

    json_attribute :dummy
    json_attribute :rating, RangeValidator
  end

  def test_recursive_validations
    x = ValidateParent.new(
      dummy: 'foo',
      rating: RangeValidator.new(stars: 6)
    )

    assert !x.valid?
    assert_equal 1, x.errors.count
  end

  class CustomValidate
    include ::ActiveJsonModel::Model

    json_attribute :dummy
    json_attribute :rating, RangeValidator

    validate :custom_validate

    def custom_validate
      errors.add(:dummy, "Dummy must have the value of 'dummy'") unless dummy == 'dummy'
    end
  end

  def test_custom_validate
    x = CustomValidate.new(
      dummy: 'foo',
      rating: RangeValidator.new(stars: 6)
    )

    assert !x.valid?
    assert_equal 2, x.errors.count
  end

  class TextCell
    include ::ActiveJsonModel::Model

    json_fixed_attribute :type, value: 'text'
    json_attribute :value, String
  end

  def test_fixed_attribute_renders
    x = TextCell.new(value: 'foo')

    assert_equal 'text', x.type
    assert_equal 'foo', x.value
    assert_equal({type: 'text', value: 'foo'}, x.dump_to_json)
  end

  def test_fixed_attribute_can_be_set_to_fixed_value
    x = TextCell.new(type: 'text', value: 'foo')
    x.type = 'text'
    assert_equal 'text', x.type
  end

  def test_fixed_attribute_cannot_be_set
    err_class = RuntimeError
    assert_raises err_class do
      TextCell.new(type: 'number', value: 'foo')
    end

    assert_raises err_class do
      x = TextCell.new(value: 'foo')
      x.type = 'number'
    end
  end
end
