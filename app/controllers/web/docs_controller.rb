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

  # Mirrors the slugs registered in
  # app/frontend/pages/Docs/data/pages/index.ts, because the page bodies are
  # bundled into the client and Rails only decides whether the route exists.
  #
  # Two lists in two languages with nothing tying them together: a page added to
  # the bundle but not here renders a 404 that looks like a missing document
  # rather than a missing line. DocsControllerTest compares the two and fails
  # when they drift.
  PAGES = %w[using-flow getting-started project-home tasks running-workflows starting-work
             sessions-and-runs session-queues assets personas agent-capabilities repositories ai-builder
             people-and-access secrets templates analytics company-workspace examples
             user-guide quick-start agents runtimes tools mcp board workflows
             triggers-and-gates integrations azure-devops configuration reference cli-ref
             api-guide config-schema user-guide-outline changelog-product-areas].freeze

  def page_exists?(slug)
    PAGES.include?(slug)
  end
end
