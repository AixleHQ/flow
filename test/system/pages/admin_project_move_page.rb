# frozen_string_literal: true

# SitePrism page object for moving a project into another company from the back
# office (Admin::ProjectMovesController): pick the target, read the preflight,
# settle the people and the cancellations, move.
class AdminProjectMovePage < SitePrism::Page
  set_url "/admin/projects{/project_id}/move/new"

  element :target_select, :select, "Target company"
  element :check_button, :button, "Check"
  element :owner_select, :select, "New owner"
  element :cancellations_checkbox, :checkbox, "Cancel the runs and sessions listed above"
  element :move_button, :button, "Move project"

  def preview(company_name)
    target_select.select(company_name)
    check_button.click
    has_move_button?(wait: 10)
  end

  def choose_member_policy(label)
    choose(label)
  end

  def move(owner_email:)
    owner_select.select(owner_email)
    cancellations_checkbox.check
    accept_confirm { move_button.click }
  end
end
