# frozen_string_literal: true

module RunnerGateway
  module V1
    # `GET /runner/v1/machine-install.sh` (docs/design/agent-runtimes/add-machine.md
    # §3.4): the script behind the "Linux service" tab of Add machine. It is
    # rendered at request time from the platform's pins (`runners.release`) by
    # Runners::MachineInstallScript.
    #
    # Public like ReleasesController (PublicRunnerEndpoint), since the operator has
    # no credential yet. Every answer is `no-store`, so a cached script cannot
    # outlive the deploy that changes the pins. No recommended version is
    # `404 not_found`.
    class MachineInstallsController < ApplicationController
      include PublicRunnerEndpoint

      def show
        version = Runners::Release.pins.recommended_version&.to_s
        digests = version && Runners::Release.checksums(version)&.binaries
        return refuse(:not_found, "not_found", "The platform recommends no runner version to install.") if digests.blank?

        render body: Runners::MachineInstallScript.render(version: version,
                                                          gateway_url: Runners::MachineRegistration.gateway_url,
                                                          digests: digests),
               content_type: "text/x-shellscript"
      end
    end
  end
end
