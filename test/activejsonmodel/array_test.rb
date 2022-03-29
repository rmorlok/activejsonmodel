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

  # class RangeValidator
  #   include ::ActiveJsonModel::Model
  #
  #   json_attribute :stars, Integer, validation: {inclusion: {in: 1..5}}
  # end
  #
  # def test_validations
  #   x = RangeValidator.new(stars: 3)
  #
  #   assert x.valid?
  #   assert_empty x.errors
  #
  #   x.stars = 6
  #
  #   assert !x.valid?
  #   assert_equal 1, x.errors.count
  # end
  #
  # class ValidateParent
  #   include ::ActiveJsonModel::Model
  #
  #   json_attribute :dummy
  #   json_attribute :rating, RangeValidator
  # end
  #
  # def test_recursive_validations
  #   x = ValidateParent.new(
  #     dummy: 'foo',
  #     rating: RangeValidator.new(stars: 6)
  #   )
  #
  #   assert !x.valid?
  #   assert_equal 1, x.errors.count
  # end
  #
  # class CustomValidate
  #   include ::ActiveJsonModel::Model
  #
  #   json_attribute :dummy
  #   json_attribute :rating, RangeValidator
  #
  #   validate :custom_validate
  #
  #   def custom_validate
  #     errors.add(:dummy, "Dummy must have the value of 'dummy'") unless dummy == 'dummy'
  #   end
  # end
  #
  # def test_custom_validate
  #   x = CustomValidate.new(
  #     dummy: 'foo',
  #     rating: RangeValidator.new(stars: 6)
  #   )
  #
  #   assert !x.valid?
  #   assert_equal 2, x.errors.count
  # end
  #
  # class TextCell
  #   include ::ActiveJsonModel::Model
  #
  #   json_fixed_attribute :type, value: 'text'
  #   json_attribute :value, String
  # end
  #
  # def test_fixed_attribute_renders
  #   x = TextCell.new(value: 'foo')
  #
  #   assert_equal 'text', x.type
  #   assert_equal 'foo', x.value
  #   assert_equal({type: 'text', value: 'foo'}, x.dump_to_json)
  # end
  #
  # def test_fixed_attribute_can_be_set_to_fixed_value
  #   x = TextCell.new(type: 'text', value: 'foo')
  #   x.type = 'text'
  #   assert_equal 'text', x.type
  # end
  #
  # def test_fixed_attribute_cannot_be_set
  #   err_class = RuntimeError
  #   assert_raises err_class do
  #     TextCell.new(type: 'number', value: 'foo')
  #   end
  #
  #   assert_raises err_class do
  #     x = TextCell.new(value: 'foo')
  #     x.type = 'number'
  #   end
  # end
  #
  # def test_fixed_attribute_cannot_be_set_from_load
  #   x = TextCell.new
  #   x.load_from_json({type: 'number', value: 'foo'})
  #
  #   assert_equal 'text', x.type
  # end
  #
  # def test_tracking_new
  #   assert TextCell.new.new?
  #   assert !TextCell.load({'type' => 'text', 'value' => 'foo'}).new?
  # end
  #
  # def test_tracking_loaded
  #   assert !TextCell.new.loaded?
  #   assert TextCell.load({'type' => 'text', 'value' => 'foo'}).loaded?
  # end
  #
  # def test_tracking_dumped
  #   assert !TextCell.new.dumped?
  #   assert !TextCell.load({'type' => 'text', 'value' => 'foo'}).dumped?
  #
  #   x = TextCell.new
  #   TextCell.dump(x)
  #   assert x.dumped?
  #
  #   x = TextCell.new
  #   x.dump_to_json
  #   assert x.dumped?
  # end
  #
  # def test_change_tracking_basic
  #   x = TextCell.new
  #   assert !x.value_changed?
  #
  #   x.value = 'foo'
  #   assert x.value_changed?
  #
  #   x.dump_to_json
  #   assert !x.value_changed?
  #
  #   x.value = 'bar'
  #   assert x.value_changed?
  #   TextCell.dump(x)
  #   assert !x.value_changed?
  #
  #   x = TextCell.new(value: 'foo')
  #   assert !x.value_changed?
  #
  #   x = TextCell.load({'type' => 'text', 'value' => 'foo'})
  #   assert !x.value_changed?
  #
  #   x = TextCell.new
  #   x.load_from_json({type: 'text', value: 'foo'})
  #   assert !x.value_changed?
  # end
  #
  # class NumberCell
  #   include ::ActiveJsonModel::Model
  #
  #   json_fixed_attribute :type, value: 'number'
  #   json_attribute :value, Integer
  # end
  #
  # class CellHolder1
  #   include ::ActiveJsonModel::Model
  #
  #   json_attribute :cell do |data|
  #     if data[:type] == 'text'
  #       TextCell
  #     else
  #       NumberCell
  #     end
  #   end
  # end
  #
  # def test_change_tracking_recursive
  #   x = CellHolder1.new(
  #     cell: NumberCell.new(
  #       value: 7
  #     )
  #   )
  #
  #   assert !x.changed?
  #
  #   x.cell.value = 8
  #
  #   assert x.changed?
  # end
  #
  # def test_polymorphic_attribute_via_block
  #   data_text = {
  #     cell: {
  #       type: 'text',
  #       value: 'foo'
  #     }
  #   }
  #
  #   data_number = {
  #     cell: {
  #       type: 'number',
  #       value: 123
  #     }
  #   }
  #
  #   holder_text = CellHolder1.load(data_text)
  #
  #   assert_instance_of TextCell, holder_text.cell
  #   assert_equal 'foo', holder_text.cell.value
  #
  #   holder_number = CellHolder1.load(data_number)
  #
  #   assert_instance_of NumberCell, holder_number.cell
  #   assert_equal 123, holder_number.cell.value
  # end
  #
  # class CellHolder2
  #   include ::ActiveJsonModel::Model
  #
  #   json_attribute :cell do |data|
  #     if data[:type] == 'text'
  #       TextCell.new(value: data[:value])
  #     else
  #       NumberCell.new(value: data[:value])
  #     end
  #   end
  # end
  #
  # def test_custom_load_attribute_via_block
  #   data_text = {
  #     cell: {
  #       type: 'text',
  #       value: 'foo'
  #     }
  #   }
  #
  #   data_number = {
  #     cell: {
  #       type: 'number',
  #       value: 123
  #     }
  #   }
  #
  #   holder_text = CellHolder2.load(data_text)
  #
  #   assert_instance_of TextCell, holder_text.cell
  #   assert_equal 'foo', holder_text.cell.value
  #
  #   holder_number = CellHolder2.load(data_number)
  #
  #   assert_instance_of NumberCell, holder_number.cell
  #   assert_equal 123, holder_number.cell.value
  # end
  #
  # class RoundTripSerialization1
  #   include ::ActiveJsonModel::Model
  #
  #   json_attribute :base64val, serialize_with: ->(value){Base64.encode64(value)} do |data|
  #     Base64.decode64(data)
  #   end
  # end
  #
  # class RoundTripSerialization2
  #   include ::ActiveJsonModel::Model
  #
  #   json_attribute :base64val,
  #                  serialize_with: ->(value){Base64.encode64(value)},
  #                  deserialize_with: ->(value) {Base64.decode64(value)}
  # end
  #
  # def test_serialization_round_trip
  #   clazz = RoundTripSerialization1
  #   x = clazz.new(base64val: 'Bob Dole')
  #
  #   assert_equal 'Bob Dole', x.base64val
  #   assert_equal({base64val: "Qm9iIERvbGU=\n"}, x.dump_to_json)
  #
  #   data = ::JSON.dump(clazz.dump(x))
  #   h = ::JSON.load(data)
  #   reconstructed = clazz.load(h)
  #
  #   assert_equal 'Bob Dole', reconstructed.base64val
  #
  #   clazz = RoundTripSerialization2
  #   x = clazz.new(base64val: 'Bob Dole')
  #
  #   assert_equal 'Bob Dole', x.base64val
  #   assert_equal({base64val: "Qm9iIERvbGU=\n"}, x.dump_to_json)
  #
  #   data = ::JSON.dump(clazz.dump(x))
  #   h = ::JSON.load(data)
  #   reconstructed = clazz.load(h)
  #
  #   assert_equal 'Bob Dole', reconstructed.base64val
  # end
  #
  # class BaseCredential
  #   include ::ActiveJsonModel::Model
  #
  #   json_attribute :secure
  #   json_polymorphic_via do |data|
  #     if data[:secure]
  #       EncryptedCredential
  #     else
  #       Credential
  #     end
  #   end
  # end
  #
  # class EncryptedCredential < BaseCredential
  #   include ::ActiveJsonModel::Model
  #
  #   json_fixed_attribute :secure, value: true
  #   json_attribute :encrypted_key, String
  # end
  #
  # class Credential < BaseCredential
  #   include ::ActiveJsonModel::Model
  #
  #   json_fixed_attribute :secure, value: false
  #   json_attribute :key, String
  # end
  #
  # class Integration
  #   include ::ActiveJsonModel::Model
  #
  #   json_attribute :credential, BaseCredential
  # end
  #
  # def test_json_polymorphic_via
  #   encrypted_credential_data = {
  #     credential: {
  #       secure: true,
  #       encrypted_key: 'asdfasfsd'
  #     }
  #   }
  #
  #   unencrypted_credential_data = {
  #     credential: {
  #       secure: false,
  #       key: 'asdfasfsd'
  #     }
  #   }
  #
  #   enc = Integration.load(encrypted_credential_data)
  #   assert_instance_of EncryptedCredential, enc.credential
  #   assert_equal true, enc.credential.secure
  #   assert_equal 'asdfasfsd', enc.credential.encrypted_key
  #
  #   unenc = Integration.load(unencrypted_credential_data)
  #   assert_instance_of Credential, unenc.credential
  #   assert_equal false, unenc.credential.secure
  #   assert_equal 'asdfasfsd', unenc.credential.key
  #
  #   # Check that the override of the secure attribute is now not settable
  #   assert_raises(RuntimeError) do
  #     unenc.credential.secure = true
  #   end
  # end
  #
  # class AfterLoad1
  #   include ::ActiveJsonModel::Model
  #
  #   attr_accessor :status
  #
  #   json_after_load do |obj|
  #     obj.status = 'loaded'
  #   end
  # end
  #
  # class AfterLoad2
  #   include ::ActiveJsonModel::Model
  #
  #   attr_accessor :status
  #
  #   json_after_load :loaded
  #
  #   def loaded
  #     self.status = 'loaded'
  #   end
  # end
  #
  # def test_after_load_callback
  #   clazz = AfterLoad1
  #   x = clazz.load({})
  #   assert_equal 'loaded', x.status
  #
  #   clazz = AfterLoad2
  #   x = clazz.load({})
  #   assert_equal 'loaded', x.status
  # end
end
