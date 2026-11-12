# frozen_string_literal: true

# "Add machine" for the two runners controllers (docs/design/agent-runtimes/DESIGN.md
# §6.3): mints a registration token for a `manual` runner and renders it, once,
# with what the install instructions need. The controller has already found the
# runner in its own scope and authorized the action.
module RunnerRegistrationTokens
  extend ActiveSupport::Concern

  REFUSAL_STATUS = {
    "runner_revoked" => :conflict,
    "runner_not_manual" => :unprocessable_entity,
    "no_runner_release" => :unprocessable_entity
  }.freeze

  private

  # The instructions point at this platform's own host: the runner gateway
  # answers on the same one (/runner/v1).
  def render_registration_token(runner)
    registration = Runners::MachineRegistration.issue!(runner, gateway_url: request.base_url)
    response.headers["Cache-Control"] = "no-store"
    render json: RunnerRegistrationResource.new(registration).to_h, status: :created
  rescue Runners::Credentials::Refused => e
    render json: { error: e.message, code: e.reason }, status: REFUSAL_STATUS.fetch(e.reason)
  end
end
