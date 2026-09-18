# frozen_string_literal: true

module RuboCop
  module Cop
    module Configuration
      # Bans reading `ENV` from application code.
      #
      # Deployment configuration has one reader: `config/settings.yml` (plus the
      # per-environment files beside it), reached from code as `Settings.*`. That
      # is what makes the configuration surface reviewable — one file lists every
      # variable, its default and why it exists, and
      # test/config/configuration_reference_test.rb can hold the documentation to
      # it. An `ENV[...]` in a service or model is invisible to all of that: the
      # variable is undocumented, its default is wherever the call site put it,
      # and nothing notices when it stops being read.
      #
      # Legal `ENV` readers live outside app code: `config/puma*.rb` and the
      # environment files (they run before the settings gem loads), `bin/*`,
      # `lib/tasks/*.rake` (task arguments are a rake idiom, not deployment
      # configuration), `db/seeds.rb`, and tests.
      #
      # To add a knob: give it a key in config/settings.yml, a row in
      # docs/reference/configuration.md, and read it as `Settings.*`.
      class NoEnvInApp < Base
        MSG = "Do not read ENV from app code. Add the key to config/settings.yml " \
              "(and a row in docs/reference/configuration.md) and read it as `Settings.*`."

        # `ENV["X"]`, `ENV.fetch("X")`, `ENV.key?("X")`, `ENV["X"] = ...`:
        # RuboCop parses index access as a plain send, so one matcher covers all.
        def_node_matcher :env_call?, <<~PATTERN
          (send (const {nil? cbase} :ENV) _ ...)
        PATTERN

        def on_send(node)
          add_offense(node) if env_call?(node)
        end

        # Bare `ENV` (passed along, iterated, merged) is just as opaque.
        def on_const(node)
          return unless node.short_name == :ENV
          return if %i[send csend].include?(node.parent&.type)

          add_offense(node)
        end
      end
    end
  end
end
