# frozen_string_literal: true

# Which sign-in methods this company accepts (AD-4, AD-7).
#
# Every refusal comes from Auth::PolicyUpdater, which holds the company row lock
# while it checks: a policy edit that would strand any active member, or would
# switch on a connection nobody has proved, never reaches the database.
class Web::Company::AuthPoliciesController < Web::Company::ApplicationController
  def index
    render inertia: "Company/AuthPolicies/Index", props: {
      providers: available_providers.map { |provider| serialize(provider) },
      scim: scim_state,
      # Shown once, straight after generation, and never read back from storage
      # — carried in the flash so it never reaches the URL or the access log.
      scim_token: flash[:scim_token]
    }
  end

  def update
    provider = find_provider!
    updater.set(provider, enabled: enabled_param)
    redirect_to company_auth_policies_path, notice: "#{provider.display_name} updated."
  rescue Auth::PolicyUpdater::Refused => e
    redirect_to company_auth_policies_path, inertia: { errors: { base: refusal_message(e) } }
  end

  private

  def scim_state
    configuration = ScimConfiguration.find_by(company: current_company)

    {
      # Always present: the admin needs to know where to point their directory
      # before they generate anything, not after.
      endpoint: "#{Settings.protocol}://#{Settings.domain}/scim",
      enabled: configuration&.enabled || false,
      last_seen_at: configuration&.last_seen_at
    }
  end

  def updater
    Auth::PolicyUpdater.new(
      company: current_company, actor: current_user, auth_session: current_auth_session
    )
  end

  # Deployment-scoped providers the installation offers, plus this company's own
  # connections. A provider belonging to another company is not found here, so a
  # guessed id is a 404 rather than a cross-tenant write.
  def available_providers
    IdentityProvider
      .where(kind: Auth::PolicyResolver.deployment_allowlist_kinds)
      .where("identity_providers.scope = 'deployment' OR identity_providers.company_id = ?", current_company.id)
      .order(:scope, :kind)
  end

  def find_provider!
    available_providers.find(params[:id])
  end

  def enabled_param
    ActiveModel::Type::Boolean.new.cast(params[:enabled])
  end

  def serialize(provider)
    policy = CompanyAuthPolicy.find_by(company: current_company, identity_provider: provider)

    {
      id: provider.id,
      kind: provider.kind.to_s,
      name: provider.display_name,
      scope: provider.scope.to_s,
      # An absent row means denied (AD-4), so a missing policy serializes as off
      # rather than as an ambiguous null.
      enabled: policy&.enabled || false,
      # Connection settings, so the screen can show and edit them. The client
      # secret is never serialized — it is write-only, like every other secret
      # in this app.
      issuer: provider.issuer,
      client_id: provider.client_id,
      tenant_id: provider.tenant_id,
      has_secret: provider.encrypted_secret.present?,
      # A connection nobody has signed in through yet cannot be enabled (AD-7),
      # and the screen says so instead of letting the toggle fail.
      proved: provider.deployment? || provider.user_identities.exists?
    }
  end

  def refusal_message(error)
    return error.message unless error.reason == :would_strand

    names = error.stranded.first(5).map(&:email).join(", ")
    suffix = error.stranded.size > 5 ? " and #{error.stranded.size - 5} more" : ""
    "#{error.message}: #{names}#{suffix}"
  end
end
