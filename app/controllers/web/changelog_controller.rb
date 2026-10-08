# frozen_string_literal: true

class Web::ChangelogController < Web::ApplicationController
  layout "inertia"

  skip_before_action :redirect_super_admin_to_admin_panel
  skip_before_action :enforce_onboarding
  skip_before_action :enforce_company_auth_policy

  def show
    render inertia: "Docs/ChangelogPage", props: {
      releases: Changelog.new(OpenSourceRepository.changelog).releases,
      source_url: OpenSourceRepository::CHANGELOG_URL,
      github_stars: InertiaRails.defer { OpenSourceRepository.stars }
    }
  end
end
