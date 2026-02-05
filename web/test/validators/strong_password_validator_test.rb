# frozen_string_literal: true

require "test_helper"

class StrongPasswordValidatorTest < ActiveSupport::TestCase
  # Test model with strong password validation
  class TestModel
    include ActiveModel::Model
    include ActiveModel::Validations

    attr_accessor :password

    validates :password, strong_password: true
  end

  setup do
    @model = TestModel.new
  end

  test "valid password passes all validations" do
    @model.password = "ValidPass1!"
    assert @model.valid?
  end

  test "nil password is valid (other validators handle presence)" do
    @model.password = nil
    assert @model.valid?
  end

  test "password too short fails validation" do
    @model.password = "Short1!"
    refute @model.valid?
    assert @model.errors[:password].any? { |e| e.include?("8 characters") }
  end

  test "password too long fails validation" do
    @model.password = "A1!" + "a" * 70  # 73 characters > 72
    refute @model.valid?
    assert @model.errors[:password].any? { |e| e.include?("72 characters") }
  end

  test "password without digit fails validation" do
    @model.password = "NoDigitHere!"
    refute @model.valid?
    assert @model.errors[:password].any? { |e| e.include?("digit") }
  end

  test "password without lowercase fails validation" do
    @model.password = "NOLOWERCASE1!"
    refute @model.valid?
    assert @model.errors[:password].any? { |e| e.include?("lowercase") }
  end

  test "password without uppercase fails validation" do
    @model.password = "nouppercase1!"
    refute @model.valid?
    assert @model.errors[:password].any? { |e| e.include?("uppercase") }
  end

  test "password without special character fails validation" do
    @model.password = "NoSpecial123"
    refute @model.valid?
    assert @model.errors[:password].any? { |e| e.include?("special") }
  end

  test "password at minimum length is valid" do
    @model.password = "Valid12!"  # 8 characters exactly
    assert @model.valid?
  end

  test "password at maximum length is valid" do
    @model.password = "A1!" + "a" * 69  # 72 characters exactly
    assert @model.valid?
  end

  test "various special characters are accepted" do
    special_chars = %w[` ! @ # $ % ^ & * ( ) - _ + = { } \[ \] | \\ ; : " < > , . / ?]

    special_chars.each do |char|
      @model.password = "ValidPa1#{char}"
      assert @model.valid?, "Password with '#{char}' should be valid but got errors: #{@model.errors.full_messages}"
    end
  end

  test "multiple validation errors are accumulated" do
    @model.password = "aa"  # Too short, no digit, no uppercase, no special
    refute @model.valid?

    errors = @model.errors[:password]
    assert errors.size >= 4, "Expected at least 4 errors, got #{errors.size}"
  end
end
