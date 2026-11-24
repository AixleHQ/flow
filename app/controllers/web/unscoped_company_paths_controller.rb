# frozen_string_literal: true

# A path from before the company's slug was part of it — /company/projects/7,
# /company/members, /user/12, /api/v1/company/assets — goes on to the same path
# in its company: a project's own, otherwise the one the person was last on.
# They stay in links already sent (chat, e-mail, trackers) and in pages a
# browser loaded before the deploy, so a write is passed on as well: 307 keeps
# its method and body.
class Web::UnscopedCompanyPathsController < Web::ApplicationController
  SECTION = %r{\A(?<api>/api/v1)?/company/(?<section>[^/]+)(?<rest>/.*)?\z}
  PROJECT = %r{\A/projects/(?<id>\d+)(?:/|\z)}

  def show
    target = unscoped_target
    return render_not_found if target.nil?
    return refuse_anonymous(target) unless signed_in?
    return refuse_without_company if current_company.nil?

    company = company_for(target)

    flash.keep
    redirect_to scoped_path(company, target), status: request.get? || request.head? ? :found : :temporary_redirect
  end

  private

  # Where the path goes once it names a company, or nil for a path that never
  # was an unscoped company path — /company/<slug>/<no such page> among them.
  def unscoped_target
    return { prefix: "", rest: "/projects" } if request.path.match?(%r{\A/company/?\z})
    return { prefix: "", rest: request.path } if request.path.start_with?("/user/")

    match = request.path.match(SECTION)
    return nil unless match && Company::RESERVED_SLUGS.include?(match[:section])

    { prefix: match[:api].to_s, rest: "/#{match[:section]}#{match[:rest]}" }
  end

  def refuse_anonymous(target)
    target[:prefix].empty? && request.get? ? redirect_to(login_path) : head(:unauthorized)
  end

  # As on every company page (Web::Company::ApplicationController): someone
  # whose memberships were all revoked is signed out.
  def refuse_without_company
    sign_out
    redirect_to login_path(error: "no_active_membership")
  end

  def company_for(target)
    project_id = target[:rest][PROJECT, :id]
    project = Project.for_user(current_user).includes(:company).find_by(id: project_id) if project_id
    project&.company || current_company
  end

  def scoped_path(company, target)
    path = "#{target[:prefix]}/company/#{company.slug}#{target[:rest]}"
    request.query_string.present? ? "#{path}?#{request.query_string}" : path
  end
end
