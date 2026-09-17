# frozen_string_literal: true

# A company's own OIDC connections (CAP-3).
#
# Creating one does NOT switch it on: AD-7 requires that an admin complete a real
# sign-in through a connection before it can be enabled, so a new connection
# arrives disabled and is turned on from the sign-in-methods screen once it has
# been proved to work.
class Web::Company::IdentityProvidersController < Web::Company::ApplicationController
  def create
    provider = current_company.identity_providers.new(
      kind: "oidc",
      scope: "company",
      name: provider_params[:name].presence || "SSO",
      config: config_from(provider_params)
    )
    provider.client_secret = provider_params[:client_secret]

    if provider.save
      # Disabled on arrival: the policy row exists so the screen can show it, and
      # enabling it goes through the AD-7 prove-before-enforce guard.
      CompanyAuthPolicy.find_or_create_by!(company: current_company, identity_provider: provider) do |policy|
        policy.enabled = false
      end
      redirect_to company_auth_policies_path,
                  notice: "#{provider.display_name} added. Sign in through it once to enable it."
    else
      redirect_to company_auth_policies_path, inertia: { errors: provider.errors }
    end
  end

  def update
    provider = company_connection!
    provider.assign_attributes(
      name: provider_params[:name].presence || provider.name,
      config: provider.config.merge(config_from(provider_params).compact)
    )
    # A blank secret means "leave it alone" — a settings form must not silently
    # erase a credential the admin did not retype.
    provider.client_secret = provider_params[:client_secret] if provider_params[:client_secret].present?

    if provider.save
      redirect_to company_auth_policies_path, notice: "#{provider.display_name} updated."
    else
      redirect_to company_auth_policies_path, inertia: { errors: provider.errors }
    end
  end

  def destroy
    provider = company_connection!
    updater.remove(provider)
    redirect_to company_auth_policies_path, notice: "Connection removed."
  rescue Auth::PolicyUpdater::Refused => e
    redirect_to company_auth_policies_path, inertia: { errors: { base: e.message } }
  end

  private

  # Scoped to this company, so a guessed id is a 404 rather than a cross-tenant
  # write.
  def company_connection!
    current_company.identity_providers.where(scope: "company").find(params[:id])
  end

  def updater
    Auth::PolicyUpdater.new(
      company: current_company, actor: current_user, user_session: current_user_session
    )
  end

  def config_from(attrs)
    {
      "issuer" => attrs[:issuer].presence,
      "client_id" => attrs[:client_id].presence,
      "tenant_id" => attrs[:tenant_id].presence
    }.compact
  end

  def provider_params
    params.permit(:name, :issuer, :client_id, :client_secret, :tenant_id)
  end
end
