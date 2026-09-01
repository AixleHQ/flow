# frozen_string_literal: true

class Web::DocsController < Web::ApplicationController
  layout "inertia"

  skip_before_action :redirect_super_admin_to_admin_panel
  skip_before_action :enforce_onboarding

  def show
    slug = (params[:slug].presence || "user-guide").downcase

    unless page_exists?(slug)
      render inertia: "Docs/DocsPage", props: { slug: slug }, status: :not_found
      return
    end

    render inertia: "Docs/DocsPage", props: {
      slug: slug
    }
  end

  private

  def page_exists?(slug)
    %w[using-flow getting-started project-home tasks running-workflows starting-work
       sessions-and-runs assets personas agent-capabilities repositories ai-builder
       people-and-access secrets analytics company-workspace examples
       user-guide quick-start agents runtimes tools mcp board workflows
       triggers-and-gates integrations configuration reference cli-ref api-guide
       config-schema user-guide-outline changelog-product-areas].include?(slug)
  end
end
