# frozen_string_literal: true

module RuboCop
  module Cop
    module Testing
      # Bans stubbing/mocking vendor-gem constants in tests (testing doctrine R2:
      # "don't mock what you don't own", docs/testing.md).
      #
      # A mock of `Octokit::Client` (or `Docker::Container`, `Kubeclient`,
      # `Temporalio`, the gitlab gem's `Gitlab::Client`) encodes our *guess*
      # about the vendor API, so tests stay green when the real API changes
      # underneath us. Stub the app-owned adapter (`Github::RepositoryService`,
      # `ContainerRuntime`, `TemporalService`, ...) or use its fake; the adapter
      # itself is contract-tested with WebMock against realistic payloads.
      #
      # Using vendor constants normally (building real objects) stays legal —
      # only `stubs` / `expects` / `unstub` / `any_instance` on them is banned.
      # Pre-doctrine offenders are frozen as per-file Excludes in .rubocop.yml.
      #
      # Scope: class-level receivers only. Stubbing a vendor *instance* held in
      # a variable is invisible to static analysis — that case is reviewer-
      # enforced via docs/testing.md R2.
      class NoVendorStubbing < Base
        MSG = "Do not stub/mock vendor `%<const>s` (testing doctrine R2, see docs/testing.md). " \
              "Stub the app-owned adapter or use its fake; contract-test the adapter with WebMock."

        RESTRICT_ON_SEND = %i[stubs expects unstub any_instance].freeze

        VENDOR_ROOTS = %w[Octokit Kubeclient Docker Temporalio].freeze

        def on_send(node)
          receiver = node.receiver
          return unless receiver&.const_type?

          full_name = receiver.source.delete_prefix("::")
          return unless vendor?(full_name)

          add_offense(node.loc.selector, message: format(MSG, const: full_name))
        end

        private

        def vendor?(full_name)
          root = full_name.split("::").first
          return true if VENDOR_ROOTS.include?(root)

          # `Gitlab` is both the gitlab gem's root and an app-owned namespace
          # (Gitlab::TokenService & co live in app/services/gitlab). Only the
          # gem's own surface is banned.
          full_name == "Gitlab" || full_name == "Gitlab::Client" || full_name.start_with?("Gitlab::Client::")
        end
      end
    end
  end
end
