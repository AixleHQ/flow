# frozen_string_literal: true

class InputValidator
  Result = Struct.new(:valid?, :errors, keyword_init: true)

  def initialize(step, available_names)
    @step = step
    @available_names = available_names.map(&:to_s)
    @errors = []
  end

  def validate!
    specs = @step.input_asset_specs
    return Result.new(valid?: true, errors: []) if specs.blank?

    specs.each do |spec|
      next if spec["required"] == false

      name = spec["name"]
      next if name.blank?
      next if @available_names.include?(name)

      @errors << "Required input missing: #{name}"
    end

    Result.new(valid?: @errors.empty?, errors: @errors)
  end
end
