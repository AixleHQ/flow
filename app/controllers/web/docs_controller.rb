# frozen_string_literal: true

class Web::DocsController < Web::ApplicationController
  layout "inertia"

  skip_before_action :redirect_super_admin_to_admin_panel
  skip_before_action :enforce_onboarding

  def show
    slug = (params[:slug].presence || "what-is-aixle").downcase

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
    %w[what-is-aixle quick-start agents install-guide configuration self-hosting cli
       tasks-overview tasks integrations permissions deploy api-guide advanced cli-ref config-schema].include?(slug)
  end
end
