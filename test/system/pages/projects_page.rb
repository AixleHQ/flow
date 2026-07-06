# frozen_string_literal: true

# SitePrism page object for the company Projects index (Projects/IndexPage) and
# its "Create New Project" modal (CreateProjectModal).
class ProjectsPage < SitePrism::Page
  set_url "/company/projects"

  # The projects index shows a header "Create Project" button and, when empty, a
  # prominent "Create Your First Project" CTA — both open the same modal.
  element :header_create_button, :button, text: "Create Project", exact_text: true
  element :empty_state_create_button, :button, text: "Create Your First Project", exact_text: true

  # Create modal
  element :name_field, :fillable_field, "Project Name"
  element :description_field, :fillable_field, "Description"
  element :submit_create, :button, text: "Create", exact_text: true

  def open_create_modal
    button = has_empty_state_create_button?(wait: 1) ? empty_state_create_button : header_create_button
    button.scroll_to(button)
    button.click
    has_name_field?(wait: 5)
  end

  def create_project(name:, description: nil)
    open_create_modal
    name_field.set(name)
    description_field.set(description) if description
    submit_create.click
  end
end
