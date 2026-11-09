# frozen_string_literal: true

module Runners
  # What the runner form exchanges with the company and the project runners
  # controllers (docs/design/agent-runtimes/DESIGN.md §3.2, §11): the runner
  # types it offers, and the attributes a submitted form may set.
  module Form
    module_function

    # One entry per type with an adapter: its config schema, which the form
    # renders from, and its capabilities.
    def runner_types
      Adapter.available_types.map do |runner_type|
        adapter = Adapter.for_type(runner_type)
        # The schema's property names are config keys, sent back by the form as
        # they are, so they are not camelized.
        {
          runner_type: runner_type,
          config_schema: DeepKeyCamelizer.verbatim(adapter.config_schema),
          capabilities: adapter.capabilities(Runner.new(runner_type: runner_type)).to_h,
          DeepKeyCamelizer::PRESERVE_MARKER => [ "configSchema" ]
        }
      end
    end

    # The attributes `params[:runner]` sets. Scope, company and author come
    # from the request, never from params. The type, `runner_type` as in the
    # model and RunnerResource, is chosen once, at creation.
    def attributes(params, creating:)
      runner = params.require(:runner)
      attributes = runner.permit(:name, :max_concurrency, :max_environments, :reuse_policy, :integration_id)
      attributes[:runner_type] = runner[:runner_type] if creating
      attributes[:config] = config(runner[:config]) if runner.key?(:config)
      attributes
    end

    # Validated whole by Runners::ConfigSchema, which refuses any key it does
    # not declare, so it is taken as sent rather than through a permit list
    # that would have to repeat the schema.
    def config(value)
      value.respond_to?(:to_unsafe_h) ? value.to_unsafe_h : value
    end
  end
end
