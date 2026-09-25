# frozen_string_literal: true

module Templates
  # Everything a template must satisfy before it is mirrored or installed. The
  # JSON Schema covers shape; this adds what a schema cannot say: references
  # between sections resolve, the step graph is acyclic, snapshots match their
  # hashes, and no secret-shaped literal hides in an MCP header.
  #
  # Run by the catalog sync AND again by the installer — the mirror is not
  # trusted to have been validated (design §4.6).
  class Validator
    InvalidPackage = Class.new(StandardError) do
      attr_reader :errors

      def initialize(errors)
        @errors = errors
        super(errors.join("; "))
      end
    end

    # A header/env value must be a config item reference or an install input.
    # Literals are refused outright: the validator does not guess which strings
    # are secrets (design §6.2).
    # An auth-scheme prefix is allowed in front of the reference ("Bearer
    # config_item:TOKEN"): session start substitutes references anywhere in the
    # string, and the prefix is a fixed word, never a value.
    REFERENCE_VALUE = /\A((Bearer|Token|Basic) )?(config_item:[A-Z][A-Z0-9_]*|\{\{\s*inputs\.[a-z][a-z0-9_]*\s*\}\})\z/
    CONFIG_ITEM_REF = /config_item:([A-Z][A-Z0-9_]*)/

    def initialize(package)
      @package = package
      @definition = package.definition
      @errors = []
    end

    def self.validate!(package)
      errors = new(package).errors
      raise InvalidPackage, errors if errors.any?

      package
    end

    def errors
      @errors = schema_errors
      # Semantic checks assume the shape the schema guarantees.
      return @errors if @errors.any?

      @errors << "the template installs nothing — add at least one agent, skill, server, tool, board or workflow" if @package.empty?
      check_unique_keys
      check_step_references
      check_depends_on
      check_triggers
      check_config_item_references
      check_mcp_values
      check_inputs
      check_files
      @errors
    end

    private

    def schema_errors
      Package.schema.validate(@definition).map do |error|
        pointer = error["data_pointer"].presence || "/"
        "#{pointer}: #{error['error']}"
      end
    end

    def keys(section) = @package.section(section).pluck("key")

    def check_unique_keys
      %w[agents skills mcp_servers tools assets workflows].each { |section| check_unique(keys(section), section) }
      check_unique(Array(@package.board&.dig("columns")).pluck("key"), "board.columns")
      check_unique(Array(@package.requires["repositories"]).pluck("key"), "requires.repositories")
      check_unique(@package.inputs.pluck("key"), "inputs")
      check_unique(@package.variables.pluck("name") + @package.secrets.pluck("name"), "config items")
      @package.section("workflows").each do |workflow|
        check_unique(workflow["steps"].pluck("key"), "workflow #{workflow['key']} steps")
      end
    end

    def check_unique(values, label)
      values.tally.select { |_, n| n > 1 }.each_key { |value| @errors << "#{label}: duplicate key #{value}" }
    end

    def check_step_references
      repository_keys = Array(@package.requires["repositories"]).pluck("key")
      references = { "tools" => keys("tools"), "skills" => keys("skills"), "mcp_servers" => keys("mcp_servers"),
                     "assets" => keys("assets"), "repositories" => repository_keys }

      @package.section("workflows").each do |workflow|
        references.each do |field, known|
          unknown_refs(Array(workflow.dig("base", field)), known, "workflow #{workflow['key']} base.#{field}")
        end
        workflow["steps"].each do |step|
          label = "workflow #{workflow['key']} step #{step['key']}"
          unknown_refs(Array(step["agent"]), keys("agents"), "#{label} agent")
          references.each { |field, known| unknown_refs(Array(step[field]), known, "#{label} #{field}") }
        end
      end
    end

    def unknown_refs(used, known, label)
      (used - known).each { |ref| @errors << "#{label}: unknown key #{ref}" }
    end

    def check_depends_on
      @package.section("workflows").each do |workflow|
        steps = workflow["steps"].index_by { |step| step["key"] }
        steps.each_value do |step|
          unknown_refs(Array(step["depends_on"]), steps.keys, "workflow #{workflow['key']} step #{step['key']} depends_on")
        end
        @errors << "workflow #{workflow['key']}: depends_on has a cycle" if cyclic?(steps)
      end
    end

    def cyclic?(steps)
      state = {}
      visit = lambda do |key|
        return true if state[key] == :visiting
        return false if state[key] == :done || !steps.key?(key)

        state[key] = :visiting
        cycle = Array(steps[key]["depends_on"]).any? { |dep| visit.call(dep) }
        state[key] = :done
        cycle
      end
      steps.keys.any? { |key| visit.call(key) }
    end

    def check_triggers
      columns = Array(@package.board&.dig("columns")).pluck("key")
      @package.section("triggers").each_with_index do |trigger, index|
        label = "triggers[#{index}]"
        unknown_refs(Array(trigger["workflow"]), keys("workflows"), "#{label} workflow")
        unknown_refs(Array(trigger["column"]), columns, "#{label} column")
        unknown_refs(Array(trigger["subject_column"]), columns, "#{label} subject_column")
        @errors << "#{label}: a schedule trigger needs cron" if trigger["kind"] == "schedule" && trigger["cron"].blank?
      end
    end

    def check_config_item_references
      known = @package.config_item_names
      used = @package.section("tools").flat_map { |tool| Array(tool["required_config_items"]) }
      @package.section("workflows").each do |workflow|
        used += Array(workflow.dig("base", "config_items"))
        workflow["steps"].each { |step| used += Array(step["config_items"]) }
      end
      custom_servers.each do |server|
        (server["headers"].to_h.values + server["env"].to_h.values).each { |value| used += value.scan(CONFIG_ITEM_REF).flatten }
      end
      (used.uniq - known).each { |name| @errors << "config item #{name} is used but not declared in variables or requires.secrets" }
    end

    def check_mcp_values
      custom_servers.each do |server|
        { "headers" => server["headers"], "env" => server["env"] }.each do |field, values|
          values.to_h.each do |name, value|
            next if value.match?(REFERENCE_VALUE)

            @errors << "mcp server #{server['name']} #{field}.#{name}: must be a config_item:NAME reference or an " \
                       "{{inputs.*}} placeholder, not a literal value"
          end
        end
      end
    end

    def custom_servers = @package.section("mcp_servers").filter_map { |server| server["custom"] }

    def check_inputs
      declared = @package.inputs.pluck("key")
      Substitution.each_string(@definition) do |value, path|
        used = Substitution.keys_in(value)
        next if used.empty?

        @errors << "#{path.join('.')}: {{inputs.*}} is not substituted in this field" unless Substitution.allowed?(path)
        (used - declared).each { |key| @errors << "#{path.join('.')}: unknown input #{key}" }
      end
      @package.inputs.each do |input|
        next unless input["type"] == "select"

        @errors << "input #{input['key']}: a select needs options" if input["options"].blank?
        if input.key?("default") && Array(input["options"]).exclude?(input["default"])
          @errors << "input #{input['key']}: default is not one of its options"
        end
      end
    end

    def check_files
      referenced_files.each do |path, expected_sha|
        if @package.file(path).nil?
          @errors << "file #{path} is referenced but missing from the package"
        elsif expected_sha && @package.sha256(path) != expected_sha
          @errors << "file #{path} does not match its sha256"
        end
      end
    end

    # path → expected sha256 (nil when the file is authored, not a snapshot)
    def referenced_files
      refs = {}
      @package.section("skills").each do |skill|
        refs[skill["path"]] = nil if skill["path"]
        refs[skill.dig("snapshot", "path")] = skill.dig("snapshot", "sha256") if skill["snapshot"]
      end
      @package.section("mcp_servers").each do |server|
        manifest = server.dig("connector", "manifest")
        refs[manifest["path"]] = manifest["sha256"] if manifest
      end
      @package.section("tools").each { |tool| Array(tool["files"]).each { |f| refs[f["from"]] = nil } }
      @package.section("assets").each { |asset| refs[asset["path"]] = nil }
      refs
    end
  end
end
