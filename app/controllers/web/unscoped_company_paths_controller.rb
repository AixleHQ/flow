# frozen_string_literal: true

# A link from before the company's slug was part of the path — /company/projects/7,
# /company/members, /user/12 — goes on to the same page in its company: a
# project's own, otherwise the one the person was last on. Such links stay in
# chat, e-mail and trackers for good, so they are read routes only: a write
# names its company in the path, never gets one picked for it.
class Web::UnscopedCompanyPathsController < Web::ApplicationController
  SECTION = %r{\A/company/(?<section>[^/]+)(?<rest>/.*)?\z}
  PROJECT = %r{\A/projects/(?<id>\d+)(?:/|\z)}

  def show
    rest = unscoped_rest
    return render_not_found if rest.nil?
    return redirect_to(login_path) unless signed_in?
    return refuse_without_company if current_company.nil?

    flash.keep
    redirect_to scoped_path(company_for(rest), rest)
  end

  private

  # The path after /company/<slug> once it names a company, or nil for a path
  # that never was an unscoped company path — /company/<slug>/<no such page>
  # among them.
  def unscoped_rest
    return "/projects" if request.path.match?(%r{\A/company/?\z})
    return request.path if request.path.start_with?("/user/")

    match = request.path.match(SECTION)
    return nil unless match && Company::RESERVED_SLUGS.include?(match[:section])

    "/#{match[:section]}#{match[:rest]}"
  end

  # As on every company page (Web::Company::ApplicationController): someone
  # whose memberships were all revoked is signed out.
  def refuse_without_company
    sign_out
    redirect_to login_path(error: "no_active_membership")
  end

  def company_for(rest)
    project_id = rest[PROJECT, :id]
    project = Project.for_user(current_user).includes(:company).find_by(id: project_id) if project_id
    project&.company || current_company
  end

  def scoped_path(company, rest)
    path = "/company/#{company.slug}#{rest}"
    request.query_string.present? ? "#{path}?#{request.query_string}" : path
  end
end
