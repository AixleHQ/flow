# frozen_string_literal: true

class Web::ProfileController < Web::ApplicationController
  layout "inertia"

  before_action :require_auth

  def show
    render inertia: "Profile/Show", props: {
      profile: CurrentUserResource.new(current_user).to_h,
      language_options: User::AGENT_LANGUAGES,
      agent_models: current_user.agent_models_for_props,
      cable_stream: inertia_cable_stream(current_user)
    }
  end

  def update
    if current_user.update(profile_params)
      redirect_to profile_path, notice: "Profile updated successfully"
    else
      redirect_to profile_path, inertia: { errors: current_user.errors }
    end
  end

  def update_default_model
    credential = current_user.agent_credentials.find(params[:agent_credential_id])
    meta = credential.metadata || {}
    if params[:default_model].present?
      meta["default_model"] = params[:default_model]
    else
      meta.delete("default_model")
    end
    credential.update!(metadata: meta)

    redirect_to profile_path, notice: "Default model updated"
  end

  def destroy_credential
    credential = current_user.agent_credentials.find(params[:agent_credential_id])
    credential.destroy!

    redirect_to profile_path, notice: "#{credential.agent_type.titleize} credentials removed"
  end

  private

  def require_auth
    redirect_to login_path unless signed_in?
  end

  def profile_params
    params.require(:profile).permit(:name, :preferred_agent_language, :default_agent_credential_id)
  end
end
