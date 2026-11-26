# frozen_string_literal: true

require "erb"
require "shellwords"

module RunnerGateway
  module V1
    # `GET /runner/v1/machine-install.sh` (docs/design/agent-runtimes/add-machine.md
    # §3.4): the script behind the "Linux service" tab of Add machine. It is
    # rendered at request time from the platform's pins (`runners.release`):
    # the recommended version, this platform's URL and the SHA-256 of each
    # pinned binary. Everything in it is a pinned value or the platform's own
    # URL, written with shell escaping; nothing comes from the request.
    #
    # Public like ReleasesController, since the operator has no credential yet.
    # Every answer is `no-store`, so a cached script cannot outlive the deploy
    # that changes the pins. No recommended version is `404 not_found`.
    class MachineInstallsController < ApplicationController
      TEMPLATE = Rails.root.join("app/views/runner_gateway/v1/machine_installs/show.sh.erb")

      skip_before_action :check_protocol

      before_action { response.set_header("Cache-Control", "no-store") }

      def show
        version = Runners::Release.pins.recommended_version&.to_s
        digests = version ? pinned_digests(version) : {}
        return refuse(:not_found, "not_found", "The platform recommends no runner version to install.") if digests.empty?

        render body: Script.new(version, Runners::MachineRegistration.gateway_url, digests).render,
               content_type: "text/x-shellscript"
      end

      private

      def pinned_digests(version)
        Runners::Release::PLATFORMS.each_with_object({}) do |platform, digests|
          pinned = Runners::Release.binary(version, platform)
          digests[platform] = pinned.sha256 if pinned
        end
      end

      # The template's binding: the three values and the one escaping helper.
      Script = Data.define(:version, :gateway_url, :digests) do
        def render
          ERB.new(TEMPLATE.read, trim_mode: "-").result(binding)
        end

        def sh(value)
          Shellwords.escape(value.to_s)
        end
      end
    end
  end
end
