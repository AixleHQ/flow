# frozen_string_literal: true

module Tools
  # Immutable metadata for one code-defined platform tool, built from the
  # `tool do ... end` block on its InternalTools::* handler class (see
  # Tools::DefinitionDSL). The definition is the single source of truth for
  # everything a tool declares about itself: wire name, description, JSON
  # input schema, tags, injection rules, integration requirement, and how it
  # projects into its reconciler-owned shadow row (Tools::Reconciler).
  class Definition
    ATTRS = %i[name display_name description input_schema tags inject_rules
               requires_integration availability unavailable_message annotations
               user_attachable managed_mcp_provider handler_class_name audience].freeze

    attr_reader(*ATTRS)

    def initialize(**attrs)
      ATTRS.each { |a| instance_variable_set(:"@#{a}", attrs[a]) }
      @tags = Array(@tags).map(&:to_sym).freeze
      @inject_rules = Array(@inject_rules).map(&:to_sym).freeze
      @input_schema = (@input_schema || {}).freeze
      @annotations = (@annotations || {}).freeze
      @user_attachable = true if @user_attachable.nil?
      @audience = (@audience || :session).to_sym
      freeze
    end

    # Reload-safe: the registry stores the class NAME and constantizes at call
    # time (maintenance_tasks pattern), never a class object that would go
    # stale across dev reloads.
    def handler_class
      handler_class_name.constantize
    end

    def available?(ctx)
      return false if requires_integration && !ctx.connected?(requires_integration)

      availability.nil? || availability.call(ctx)
    end

    def inject?(ctx)
      inject_rules.any? { |rule| InjectionRules.fetch(rule).call(ctx) }
    end

    def unavailable_message
      @unavailable_message ||
        "The #{requires_integration} integration is not connected for this project. " \
        "Connect it in Project Settings → Integrations."
    end

    # Projection into the shadow row.
    def to_row_attributes
      {
        name: name.to_s,
        display_name: display_name,
        description: description,
        input_schema: input_schema.as_json,
        tags: tags.map(&:to_s),
        requires_integration: requires_integration&.to_s,
        user_attachable: user_attachable,
        execution_mode: "app",
        source: "code",
        deleted_at: nil,
        scope_type: nil,
        scope_id: nil
      }
    end
  end
end
