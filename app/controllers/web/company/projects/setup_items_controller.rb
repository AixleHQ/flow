# frozen_string_literal: true

# One action on one checklist item. `operation` picks it; the service checks the
# item belongs to this install and is of the right kind.
class Web::Company::Projects::SetupItemsController < Web::Company::Projects::ApplicationController
  OPERATIONS = %w[add_secret attach_repository activate recheck dismiss].freeze

  def update
    install = current_project.template_installs.find(params[:template_install_id])
    item = install.setup_items.find(params[:id])
    checklist = Templates::SetupChecklist.new(install, user: current_user)

    case params[:operation].to_s
    when "add_secret" then checklist.add_secret!(item, params[:value].to_s)
    when "attach_repository" then checklist.attach_repository!(item, params[:repository_id])
    when "activate" then checklist.activate_trigger!(item)
    when "recheck" then checklist.recheck!(item)
    when "dismiss" then checklist.dismiss!(item)
    else return redirect_back_to(install, alert: "Unknown action")
    end
    redirect_back_to(install, notice: params[:operation] == "recheck" ? "Checking again — reload in a moment." : nil)
  rescue Templates::SetupChecklist::Error => e
    redirect_back_to(install, alert: e.message)
  end

  private

  def redirect_back_to(install, **flash)
    redirect_to company_project_template_install_path(current_project, install), flash.compact
  end
end
