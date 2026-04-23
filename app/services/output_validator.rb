# frozen_string_literal: true

class OutputValidator
  Result = Struct.new(:valid?, :errors, keyword_init: true)

  def initialize(step, collected_assets)
    @step = step
    @collected_assets = collected_assets
    @errors = []
  end

  def validate!
    specs = @step.output_asset_specs
    return Result.new(valid?: true, errors: []) if specs.blank?

    specs.each do |spec|
      validate_spec(spec)
    end

    Result.new(valid?: @errors.empty?, errors: @errors)
  end

  private

  def validate_spec(spec)
    required = spec["required"] != false
    name_pattern = spec["name_pattern"]
    min_size = spec["min_size"]
    required_sections = spec["required_sections"]

    matching = find_matching_assets(name_pattern, spec["name"])

    if matching.empty? && required
      @errors << "Required output missing: #{spec['name'] || name_pattern}"
      return
    end

    matching.each do |asset|
      validate_size(asset, min_size) if min_size
      validate_sections(asset, required_sections) if required_sections.present?
    end
  end

  def find_matching_assets(pattern, name)
    @collected_assets.select do |asset|
      if pattern.present?
        Regexp.new(pattern).match?(asset.name)
      elsif name.present?
        asset.name == name
      else
        false
      end
    end
  rescue RegexpError => e
    Rails.logger.warn("[OutputValidator] Invalid regexp '#{pattern}': #{e.message}")
    []
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
