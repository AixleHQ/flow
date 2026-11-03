# frozen_string_literal: true

# Draws the routes of one process mode (config/routes.rb) for a block, and puts
# the default routes back afterwards. The test process boots as the web
# process, so a test of the runner gateway draws the gateway's routes:
#
#   with_process_mode("runner_gateway") { post "/runner/v1/register", ... }
#
# or, for a whole test class, `include ProcessModeHelper::RunnerGateway`.
module ProcessModeHelper
  VARIABLE = "AIXLE_PROCESS_MODE"

  def with_process_mode(mode)
    draw_routes_for(mode)
    yield
  ensure
    draw_routes_for(nil)
  end

  def draw_routes_for(mode)
    mode.nil? ? ENV.delete(VARIABLE) : ENV[VARIABLE] = mode
    Rails.application.reload_routes!
  end

  # Every test of the including class runs against the gateway's routes.
  module RunnerGateway
    extend ActiveSupport::Concern
    include ProcessModeHelper

    included do
      setup { draw_routes_for("runner_gateway") }
      teardown { draw_routes_for(nil) }
    end
  end
end
