# frozen_string_literal: true

class OutputValidator
  Result = Struct.new(:valid?, :errors, keyword_init: true)

  def initialize(step, collected_assets)
    @step = step
    @collected_assets = collected_assets
    @errors = []
  end

  def validate!
    @step.output_specs.each do |spec|
      validate_spec(spec) unless spec.blank?
    end

    Result.new(valid?: @errors.empty?, errors: @errors)
  end

  private

  def validate_spec(spec)
    if spec.name_pattern_invalid? && spec.required?
      @errors << "Output pattern #{spec.name_pattern} is not a valid regular expression"
      return
    end

    matching = @collected_assets.select { |asset| spec.matches?(asset.name) }

    if matching.empty? && spec.required?
      @errors << "Required output missing: #{spec.label}"
      return
    end

    min_size = spec.attributes["min_size"]
    required_sections = spec.attributes["required_sections"]
    matching.each do |asset|
      validate_size(asset, min_size) if min_size
      validate_sections(asset, required_sections) if required_sections.present?
    end
  end

  def validate_size(asset, min_size)
    return unless asset.file_size.to_i < min_size.to_i

    @errors << "Output '#{asset.name}' is too small (#{asset.file_size} bytes, min: #{min_size})"
  end

  def validate_sections(asset, required_sections)
    return unless asset.content_type&.include?("markdown") || asset.name.end_with?(".md")
    return unless asset.file

    content = asset.file.read
    required_sections.each do |section|
      unless content.match?(/^#+\s+#{Regexp.escape(section)}/i)
        @errors << "Output '#{asset.name}' missing required section: '#{section}'"
      end
    end
  rescue StandardError => e
    Rails.logger.warn("[OutputValidator] Could not read #{asset.name}: #{e.message}")
  end
end
