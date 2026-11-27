# frozen_string_literal: true

module Templates
  # The templates repository's CI gate (design §6.3), run against a checkout:
  #
  #   bin/rails templates:validate ROOT=path/to/flow-templates \
  #     [BASE=path/to/base-checkout] [AUTHOR=github-login] [AUTHOR_IS_MAINTAINER=true]
  #
  # The same Templates::Validator every installation runs, plus the rules that
  # only make sense for the repository:
  # - templates live at templates/<namespace>/<slug>/ and say so in template.yaml;
  # - every namespace is registered in namespaces.yaml;
  # - a template that asks for setup explains it in SETUP.md;
  # - a changed template has a higher version than on the base branch;
  # - with AUTHOR: the author owns every namespace whose templates changed.
  #   Owners come from the BASE branch for an existing namespace, so a pull
  #   request cannot add its own author to someone else's namespace; a new
  #   namespace is owned by whoever the pull request lists, and the maintainers'
  #   required review of namespaces.yaml (CODEOWNERS) is what approves it.
  class RepositoryValidator
    REGISTRY_KEY = NamespaceRegistry::FILE

    def self.call(...) = new(...).call

    def initialize(root:, base_root: nil, author: nil, author_is_maintainer: false)
      @root = Pathname(root)
      @base_root = base_root && Pathname(base_root)
      @author = author.presence
      @author_is_maintainer = author_is_maintainer
    end

    # @return [Hash{String => Array<String>}] "namespace/slug" (or namespaces.yaml) → errors
    def call
      errors = Hash.new { |h, k| h[k] = [] }
      registry = NamespaceRegistry.parse(read(@root, REGISTRY_KEY))
      base_registry = @base_root && NamespaceRegistry.parse(read(@base_root, REGISTRY_KEY))
      errors[REGISTRY_KEY].concat(registry.errors)
      errors[REGISTRY_KEY].concat(stray_files(@root))

      template_dirs(@root).each do |dir|
        identifier = identifier_for(dir)
        problems = check(dir, identifier, registry)
        problems.concat(ownership_errors(identifier, registry, base_registry)) if changed?(dir, identifier)
        errors[identifier].concat(problems)
      end
      errors.reject { |_, problems| problems.empty? }
    end

    # Advice that does not fail the gate: a step whose text names a platform tool the
    # step does not list (docs/design/tool-attachment.md §5.2). A session gets only the
    # tools its workflow or step lists, so the step could not call it. A prohibition
    # ("do not call board_move_task") warns too; that is accepted for a warning.
    #
    # @return [Hash{String => Array<String>}] "namespace/slug" → warnings
    def warnings
      template_dirs(@root).each_with_object({}) do |dir, found|
        package = loadable_package(dir)
        next unless package

        messages = unlisted_tool_warnings(package)
        found[identifier_for(dir)] = messages if messages.any?
      rescue Psych::Exception
        next # call reports the malformed definition
      end
    end

    private

    # A directory that does not load or does not validate is reported by `call`, so
    # `warnings` skips it instead of raising.
    def loadable_package(dir)
      return unless dir.join(Package::DEFINITION_FILE).file?

      package = Package.from_directory(dir)
      package if Validator.new(package).errors.empty?
    end

    def unlisted_tool_warnings(package)
      platform_names = platform_tool_names
      keys_to_names = package.section("tools").to_h { |tool| [ tool["key"].to_s.downcase, tool["platform"] || tool["name"] ] }
      agents = package.section("agents").index_by { |agent| agent["key"] }

      package.section("workflows").flat_map do |workflow|
        base_tools = Array(workflow.dig("base", "tools"))
        Array(workflow["steps"]).flat_map do |step|
          listed = (base_tools + Array(step["tools"])).map { |key| keys_to_names[key.to_s.downcase] || key }
          named = named_tools(step_texts(step, agents[step["agent"]]), platform_names, keys_to_names)
          (named - listed).sort.map do |name|
            "workflow #{workflow['key']} step #{step['key']} names #{name} but does not list it in tools"
          end
        end
      end
    end

    def step_texts(step, agent)
      texts = [ step["instructions"] ]
      texts += Array(step["sub_steps"]).flat_map { |sub| [ sub["name"], sub["instructions"] ] }
      texts += agent.values_at("persona", "principles", "title", "communication_style") if agent
      texts.compact.map(&:to_s)
    end

    # Names of the platform tools in the text, plain or as a {{tool:<key>}} reference.
    def named_tools(texts, platform_names, keys_to_names)
      text = texts.join("\n")
      plain = platform_names.select { |name| text.match?(/(?<![a-z0-9_])#{Regexp.escape(name)}(?![a-z0-9_])/i) }
      referenced = text.scan(/\{\{tool:([^}\s]+)\}\}/i).flatten.filter_map { |key| keys_to_names[key.downcase] }
      (plain + referenced).uniq
    end

    def platform_tool_names
      Tools::Registry.definitions.values.select { |d| d.audience == :session && d.user_attachable && d.inject_rules.empty? }.map(&:name)
    end

    def read(root, file)
      path = root.join(file)
      path.file? ? path.read : nil
    end

    def template_dirs(root)
      base = root.join(CatalogSync::TEMPLATES_DIR)
      return [] unless base.directory?

      base.children.select(&:directory?).flat_map { |ns| ns.children.select(&:directory?) }.sort
    end

    # A template directory directly under templates/ is the pre-namespace layout.
    def stray_files(root)
      base = root.join(CatalogSync::TEMPLATES_DIR)
      return [] unless base.directory?

      base.children.select(&:directory?).filter_map do |ns|
        next unless ns.join(Package::DEFINITION_FILE).file?

        "templates/#{ns.basename} is a template outside a namespace — move it to templates/<namespace>/#{ns.basename}"
      end
    end

    def identifier_for(dir) = "#{dir.dirname.basename}/#{dir.basename}"

    def check(dir, identifier, registry)
      return [ "#{Package::DEFINITION_FILE} is missing" ] unless dir.join(Package::DEFINITION_FILE).file?

      namespace = identifier.split("/").first
      package = Package.from_directory(dir)
      errors = Validator.new(package).errors
      errors << "namespace #{namespace} is not registered in #{REGISTRY_KEY}" unless registry[namespace]
      errors << "directory does not match namespace/slug #{package.identifier.inspect}" if package.identifier != identifier
      errors << "#{Package::SETUP_FILE} is required when the template has requirements" if needs_setup?(package)
      errors << "#{Package::README_FILE} is missing" if package.readme.blank?
      errors.concat(version_errors(package, identifier))
      errors
    rescue Psych::Exception => e
      [ "#{Package::DEFINITION_FILE}: #{e.message}" ]
    end

    def needs_setup?(package)
      requirements = package.requires.values_at("integrations", "repositories", "secrets").flatten.compact
      requirements.any? && package.setup_markdown.blank?
    end

    def base_package(identifier)
      dir = @base_root&.join(CatalogSync::TEMPLATES_DIR, identifier)
      dir&.join(Package::DEFINITION_FILE)&.file? ? Package.from_directory(dir) : nil
    rescue Psych::Exception
      nil
    end

    def changed?(dir, identifier)
      return true unless @base_root

      base = base_package(identifier)
      base.nil? || base.digest != Package.from_directory(dir).digest
    rescue Psych::Exception
      true
    end

    def version_errors(package, identifier)
      base = base_package(identifier)
      return [] if base.nil? || base.digest == package.digest || package.version.to_i > base.version.to_i

      [ "changed since the base branch but version is still #{package.version} — increase it" ]
    end

    def ownership_errors(identifier, registry, base_registry)
      return [] if @author.nil? || @author_is_maintainer

      namespace = identifier.split("/").first
      owners_from = base_registry&.[](namespace) ? base_registry : registry
      return [] if owners_from.owner?(namespace, @author)

      [ "#{@author} is not an owner of the #{namespace} namespace (#{REGISTRY_KEY})" ]
    end
  end
end
