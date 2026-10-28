# frozen_string_literal: true

if ENV["RUBY_LSP"] == "1"
  return
end

# Typelizer reads a column's values only from a Rails `enum`. Our models declare
# them with enumerize and AASM instead, so such a column comes out as `string`
# unless the resource repeats the values in a `typelize`. This plugin reads them
# from the model too, and a resource that exposes the column as it is gets the
# union with no annotation.
#
# It applies to the models in INFERRED_ENUM_MODELS. Turning it on for every
# model narrows about thirty generated types at once, and the frontend code and
# tests that still pass plain strings (or values a column does not have) must be
# fixed in the same change, so models join the list one at a time.
module TypelizerModelPlugin
  INFERRED_ENUM_MODELS = %w[
    Agent
    AssetVersion
    BoardActivity
    BoardTask
    ColumnTransition
    ColumnWorkflowBinding
    CompanyMembership
    ConfigItem
    Runner
  ].freeze

  def self.new(model_class:, config:)
    plugin = model_class && model_class < ::ActiveRecord::Base ? ActiveRecord : Typelizer::ModelPlugins::Poro
    plugin.new(model_class: model_class, config: config)
  end

  class ActiveRecord < Typelizer::ModelPlugins::ActiveRecord
    # Inline unions, as `typelize %w[...]` wrote them: no named enum type.
    def enum_for(prop)
      # Same contract as super: an association or nested prop is typed by its
      # serializer, and a same-named column says nothing about it.
      return if serializer_resolved_type?(prop)

      rails_enum = super
      return rails_enum if rails_enum || !INFERRED_ENUM_MODELS.include?(model_class.name)

      prop.enum = enumerized_values(prop) || aasm_states(prop)
    end

    private

    def enumerized_values(prop)
      return unless model_class.respond_to?(:enumerized_attributes)

      model_class.enumerized_attributes[prop.column_name.to_s]&.values&.map(&:to_s)
    end

    # Read from the store, which never creates a machine the model lacks.
    def aasm_states(prop)
      return unless defined?(AASM::StateMachineStore)

      store = AASM::StateMachineStore.fetch(model_class, true)
      machine = store&.machine_names&.map { |name| store.machine(name) }&.find do |candidate|
        candidate.config.column.to_s == prop.column_name.to_s
      end
      machine&.states&.map { |state| state.name.to_s }
    end
  end
end

Typelizer.configure do |config|
  config.output_dir = Rails.root.join("app/frontend/types/generated")
  config.types_import_path = "@/types/generated"
  config.null_strategy = :nullable
  config.comments = true
  config.model_plugin = TypelizerModelPlugin

  config.properties_transformer = lambda { |properties|
    properties.map { |prop| prop.dup.tap { |p| p.name = prop.name.to_s.camelize(:lower) } }
  }

  config.serializer_model_mapper = lambda { |serializer|
    model_name = serializer.name.delete_suffix("Resource")
    model_name = "User" if model_name == "CurrentUser"
    model_name.safe_constantize
  }
end
