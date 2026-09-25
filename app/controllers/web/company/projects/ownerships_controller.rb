# frozen_string_literal: true

class Web::Company::Projects::OwnershipsController < Web::Company::Projects::ApplicationController
  def update
    new_owner = User.find_by(id: params.require(:ownership)[:user_id])

    if current_project.transfer_ownership_to(new_owner)
      redirect_back fallback_location: company_project_settings_path(current_project),
                    notice: "Ownership transferred to #{new_owner.name.presence || new_owner.email}."
    else
      redirect_back fallback_location: company_project_settings_path(current_project),
                    inertia: { errors: current_project.errors }
    end
  end
end
