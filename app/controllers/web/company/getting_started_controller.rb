# frozen_string_literal: true

# The page a new member lands on after onboarding until they finish or skip
# their product tour (AuthConcern#app_home_path, docs/design/product-tour.md).
class Web::Company::GettingStartedController < Web::Company::ApplicationController
  requires_feature :product_tour

  def show
    render inertia: "GettingStarted/GettingStartedPage", props: {
      hello_flow_available: ProductTour.hello_flow_available?,
      hello_flow_path: template_path(*ProductTour::HELLO_FLOW.values),
      has_projects: accessible_projects.exists?
    }
  end

  # AI Builder lives in a project, so a member with none gets one first.
  def build_with_ai
    project = accessible_projects.order(created_at: :desc).first ||
              current_company.projects.create!(name: new_project_name, owner: current_user)

    redirect_to company_project_aixle_builder_path(project)
  end

  private

  # Project names are unique in a company, and a project this member cannot see
  # may already hold the plain name.
  def new_project_name
    taken = current_company.projects.where("name LIKE ?", "New Project%").pluck(:name).to_set
    (1..).lazy.map { |n| n == 1 ? "New Project" : "New Project #{n}" }.find { |name| !taken.include?(name) }
  end

  def accessible_projects
    Project.for_user(current_user).for_company(current_company).with_state(:active)
  end
end
