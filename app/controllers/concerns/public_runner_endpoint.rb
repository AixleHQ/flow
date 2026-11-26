# frozen_string_literal: true

# The handling shared by the public endpoints of the runner gateway
# (`ReleasesController`, `MachineInstallsController`): the caller is an
# operator who has no token and sends no protocol headers yet, so the protocol
# check is skipped. Every answer, the refusals included, is
# `Cache-Control: no-store` (PROTOCOL.md §2), so a cached answer cannot outlive
# the deploy that changes the pins.
module PublicRunnerEndpoint
  extend ActiveSupport::Concern

  included do
    skip_before_action :check_protocol

    before_action { response.set_header("Cache-Control", "no-store") }
  end
end
