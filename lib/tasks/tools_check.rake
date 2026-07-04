# frozen_string_literal: true

namespace :tools do
  desc "Drift check: code registry vs tools rows, name hygiene, schema sanity. " \
       "Exit 0 = clean, 2 = drift found, 1 = check itself broke (Terraform-plan exit-code contract)."
  task check: :environment do
    findings = Hash.new { |h, k| h[k] = [] }

    definitions = Tools::Registry.definitions

    # 1. Definition hygiene: name format (app + MCP spec charset) and schema shape.
    definitions.each_value do |d|
      findings[:bad_definition] << "#{d.name}: invalid name format" unless d.name.match?(/\A[a-z][a-z0-9_]*\z/)
      findings[:bad_definition] << "#{d.name}: name exceeds MCP 128-char guidance" if d.name.length > 128
      findings[:bad_definition] << "#{d.name}: handler missing" unless d.handler_class.instance_method(:execute)
      schema = d.input_schema
      findings[:bad_definition] << "#{d.name}: input_schema root must be type=object" unless schema["type"] == "object"
      findings[:bad_definition] << "#{d.name}: input_schema uses root $ref" if schema.key?("$ref")
    rescue NameError => e
      findings[:bad_definition] << "#{d.name}: handler class not resolvable (#{e.message})"
    end

    # 2. Shadow rows vs registry.
    code_rows = Tool.code_source.not_deleted.index_by(&:name)
    (definitions.keys - code_rows.keys).each { |n| findings[:missing_row] << n }
    (code_rows.keys - definitions.keys).each { |n| findings[:orphan_row] << n }
    definitions.each_value do |d|
      row = code_rows[d.name] or next
      desired = d.to_row_attributes
      if row.input_schema.as_json != desired[:input_schema].as_json ||
         row.display_name != desired[:display_name] ||
         row.description != desired[:description] ||
         row.tags != desired[:tags] ||
         row.requires_integration != desired[:requires_integration]
        findings[:definition_mismatch] << d.name
      end
    end

    # 3. Custom-tool name hygiene (grandfathered rows the model validation can't reject retroactively).
    Tool.db_source.not_deleted.find_each do |tool|
      findings[:custom_name_collision] << "#{tool.name} (##{tool.id})" if definitions.key?(tool.name)
      findings[:custom_reserved_namespace] << "#{tool.name} (##{tool.id})" if tool.name.start_with?("mcp__")
    end

    # 4. Workflow step configs referencing soft-deleted or missing tool rows.
    if defined?(Step) && Step.column_names.include?("tool_ids")
      live_ids = Tool.not_deleted.pluck(:id).to_set
      Step.where.not(tool_ids: []).find_each do |step|
        dangling = Array(step.tool_ids).reject { |id| live_ids.include?(id) }
        findings[:dangling_step_tool_ids] << "step ##{step.id}: #{dangling.join(', ')}" if dangling.any?
      end
    end

    findings.reject! { |_, v| v.empty? }

    if findings.empty?
      puts "tools:check — clean (#{definitions.size} definitions, #{code_rows.size} shadow rows)"
    else
      findings.each do |kind, items|
        puts "tools:check [#{kind}] (#{items.size}):"
        items.each { |item| puts "  - #{item}" }
      end
      exit 2
    end
  end
end
