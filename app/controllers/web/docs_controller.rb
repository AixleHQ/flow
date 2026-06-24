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
    %w[user-guide quick-start agents runtimes tools mcp board workflows
       workflow-triggers integrations configuration reference cli-ref api-guide
       config-schema].include?(slug)
  end
end
