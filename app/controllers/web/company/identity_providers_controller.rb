# frozen_string_literal: true

# A company's own OIDC connections (CAP-3).
#
# Creating one does NOT switch it on: AD-7 requires that an admin complete a real
# sign-in through a connection before it can be enabled, so a new connection
# arrives disabled and is turned on from the sign-in-methods screen once it has
# been proved to work.
class Web::Company::IdentityProvidersController < Web::Company::ApplicationController
  def create
    kind = provider_params[:kind] == "saml" ? "saml" : "oidc"
    provider = current_company.identity_providers.new(
      kind: kind,
      scope: "company",
      name: provider_params[:name].presence || "SSO",
      config: config_from(provider_params).merge(kind == "saml" ? saml_keys : {})
    )
    provider.client_secret = provider_params[:client_secret] if kind == "oidc"

    return redirect_to(company_auth_policies_path, inertia: { errors: { base: "SAML is not available on this installation." } }) if kind == "saml" && !SsoBridge::Client.configured?

    if provider.save
      register_with_bridge(provider) if kind == "saml"
      # Disabled on arrival: the policy row exists so the screen can show it, and
      # enabling it goes through the AD-7 prove-before-enforce guard.
      CompanyAuthPolicy.find_or_create_by!(company: current_company, identity_provider: provider) do |policy|
        policy.enabled = false
      end
      redirect_to company_auth_policies_path, notice: "#{provider.display_name} added. Sign in through it once to enable it."
    else
      redirect_to company_auth_policies_path, inertia: { errors: provider.errors }
    end
  rescue SsoBridge::Client::Error => e
    # The row and the bridge must not drift: if the bridge refused, the local
    # connection is worthless and is rolled back rather than left as a stub that
    # dead-ends at sign-in.
    provider&.destroy
    redirect_to company_auth_policies_path, inertia: { errors: { base: "The SAML bridge refused this connection: #{e.message}" } }
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
    detach_from_bridge(provider) if provider.saml?
    updater.remove(provider)
    redirect_to company_auth_policies_path, notice: "Connection removed."
  rescue Auth::PolicyUpdater::Refused => e
    redirect_to company_auth_policies_path, inertia: { errors: { base: e.message } }
  end

  private

  # Best effort: a bridge that is down must not block removing a connection
  # locally, because the local row is what the gate reads.
  def detach_from_bridge(provider)
    return unless SsoBridge::Client.configured?

    SsoBridge::Client.new.delete_connection(
      tenant: provider.config["tenant"], product: provider.config["product"]
    )
  rescue SsoBridge::Client::Error => e
    Rails.logger.warn("[SsoBridge] could not remove connection: #{e.message}")
  end

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

  # The bridge identifies a connection by tenant+product. Deriving the tenant
  # from the company id rather than letting an admin type it keeps two customers
  # from colliding on the same bridge.
  def saml_keys
    {
      "tenant" => "company-#{current_company.id}",
      "product" => Settings.project_name.to_s.downcase
    }
  end

  def register_with_bridge(provider)
    SsoBridge::Client.new.upsert_connection(
      tenant: provider.config["tenant"],
      product: provider.config["product"],
      name: provider.display_name,
      metadata_url: provider_params[:metadata_url].presence,
      raw_metadata: provider_params[:raw_metadata].presence,
      redirect_url: "#{Settings.protocol}://#{Settings.domain}",
      default_redirect_url: "#{Settings.protocol}://#{Settings.domain}#{oidc_callback_path}"
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
    params.permit(:name, :kind, :issuer, :client_id, :client_secret, :tenant_id,
                  :metadata_url, :raw_metadata)
  end
end
