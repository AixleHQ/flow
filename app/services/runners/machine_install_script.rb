# frozen_string_literal: true

require "erb"
require "shellwords"

module Runners
  # The `machine-install.sh` of the "Linux service" tab of Add machine
  # (docs/design/agent-runtimes/add-machine.md §3.4), rendered from the
  # platform's pins: the version, this platform's URL and the SHA-256 of each
  # pinned binary. Everything in it is a pinned value or the platform's own URL,
  # written with shell escaping; nothing comes from a request.
  #
  #   Runners::MachineInstallScript.render(version: "0.6.0", gateway_url: "https://…",
  #                                        digests: { "linux-amd64" => "…" })
  module MachineInstallScript
    TEMPLATE = Rails.root.join("app/views/runner_gateway/v1/machine_installs/show.sh.erb")

    # The template's binding: the three values and the one escaping helper.
    Script = Data.define(:version, :gateway_url, :digests) do
      def render
        ERB.new(TEMPLATE.read, trim_mode: "-").result(binding)
      end

      def sh(value)
        Shellwords.escape(value.to_s)
      end
    end

    module_function

    def render(version:, gateway_url:, digests:)
      Script.new(version: version.to_s, gateway_url: gateway_url, digests: digests).render
    end
  end
end
