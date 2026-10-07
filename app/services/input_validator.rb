# frozen_string_literal: true

class InputValidator
  Result = Struct.new(:valid?, :errors, keyword_init: true)

  def initialize(step, available_names)
    @step = step
    @available_names = available_names.map(&:to_s)
    @errors = []
  end

  def validate!
    @step.input_specs.each do |spec|
      next unless spec.required? && spec.name
      next if @available_names.any? { |name| spec.matches?(name) }

      @errors << "Required input missing: #{spec.name}"
    end

    Result.new(valid?: @errors.empty?, errors: @errors)
  end
end
