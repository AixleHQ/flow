# frozen_string_literal: true

module RuboCop
  module Cop
    module Testing
      # Bans Mocha's `any_instance` in tests (testing doctrine R6, docs/testing.md).
      #
      # `any_instance` couples the test to whichever instance happens to be
      # created inside the code under test and leaks stubbing across objects.
      # Inject the dependency, stub an app-owned seam, or use a fake instead.
      #
      # Files that used `any_instance` before the doctrine landed are frozen as
      # per-file Excludes in .rubocop.yml — that list only ever shrinks.
      class NoAnyInstance < Base
        MSG = "Do not use `any_instance` (testing doctrine R6, see docs/testing.md). " \
              "Inject the dependency, stub an app-owned seam, or use a fake."

        RESTRICT_ON_SEND = %i[any_instance].freeze

        def on_send(node)
          add_offense(node.loc.selector)
        end
      end
    end
  end
end
