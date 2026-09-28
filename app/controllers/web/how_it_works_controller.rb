# frozen_string_literal: true

# What the product does and what it costs, with the numbers the sales team
# quotes. Public on purpose — it is the page the signup form links to, and the
# visitor reading it has no account yet.
#
# Only where we host: it sells a workspace a stranger can create and a price we
# invoice. A self-hosted operator charges nobody, and a Marketplace installation
# belongs to the customer who already bought it — in neither is there anything
# here to read.
class Web::HowItWorksController < Web::ApplicationController
  layout "inertia"

  skip_before_action :enforce_onboarding
  skip_before_action :redirect_super_admin_to_admin_panel
  # A signed-in visitor with no workspace is otherwise sent straight back to the
  # signup form — which is the page that linked them here to read this first.
  skip_before_action :enforce_workspace

  before_action :require_self_serve_signup

  def show
    render inertia: "HowItWorks/ShowPage", props: {
      queue_hourly_rate: Settings.pricing.queue_hourly_rate.to_f,
      signed_in: signed_in?
    }
  end

  private

  def require_self_serve_signup
    redirect_to root_path unless Deployment.saas?
  end
end
