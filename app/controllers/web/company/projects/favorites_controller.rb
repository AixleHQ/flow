# frozen_string_literal: true

# Star / unstar a project for the CURRENT user, from the project tiles on
# /company/projects. Both actions are idempotent, so the star survives a
# double-click or a replayed request without erroring at the user.
#
# `redirect_back` rather than a redirect to the project list: the toggle is a
# tile-level action and the caller keeps its scroll position and client-side
# filters (`preserveState`), so the answer is "re-render where you are with
# fresh props" — the shared sidebar list re-orders from the same response.
class Web::Company::Projects::FavoritesController < Web::Company::Projects::ApplicationController
  def create
    current_user.project_favorites.find_or_create_by!(project: current_project)

    redirect_back fallback_location: company_projects_path
  end

  def destroy
    current_user.project_favorites.find_by(project: current_project)&.destroy

    redirect_back fallback_location: company_projects_path
  end
end
