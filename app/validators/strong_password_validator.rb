# frozen_string_literal: true

class StrongPasswordValidator < ActiveModel::EachValidator
  MIN_LENGTH = 8
  MAX_LENGTH = 72
  AT_LEAST_ONE_DIGIT = /[\d]{1}/
  AT_LEAST_ONE_LOWERCASE = /[a-z]+/
  AT_LEAST_ONE_UPPERCASE = /[A-Z]+/
  AT_LEAST_ONE_SPECIAL = %r{[`!@#$%^&*()\-_+={}\[\]|\\;:"<>,./?]}

  def validate_each(record, attribute, value)
    return if value.nil?

    record.errors.add(attribute, :invalid_min_length, min: MIN_LENGTH) if value.size < MIN_LENGTH
    record.errors.add(attribute, :invalid_max_length, max: MAX_LENGTH) if value.size > MAX_LENGTH
    record.errors.add(attribute, :at_least_one_digit) unless value.match?(AT_LEAST_ONE_DIGIT)
    record.errors.add(attribute, :at_least_one_lowercase) unless value.match?(AT_LEAST_ONE_LOWERCASE)
    record.errors.add(attribute, :at_least_one_uppercase) unless value.match?(AT_LEAST_ONE_UPPERCASE)
    record.errors.add(attribute, :at_least_one_special) unless value.match?(AT_LEAST_ONE_SPECIAL)
  end
end
