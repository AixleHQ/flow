# frozen_string_literal: true

# The company's SCIM endpoint credential (CAP-6).
#
# The token is shown exactly once, at generation. It is a password: storing it
# retrievably so an admin can look it up later would make every subsequent
# database read a credential disclosure.
class Web::Company::ScimConfigurationsController < Web::Company::ApplicationController
  def create
    configuration = ScimConfiguration.find_or_initialize_by(company: current_company)
    configuration.token_digest ||= "pending-#{SecureRandom.hex(8)}"
    configuration.enabled = true
    configuration.save!
    token = configuration.regenerate_token!

    redirect_to company_auth_policies_path(scim_token: token),
                notice: "Directory sync token generated. Copy it now — it is not shown again."
  end

  def destroy
    ScimConfiguration.find_by(company: current_company)&.update!(enabled: false)
    redirect_to company_auth_policies_path, notice: "Directory sync turned off."
  end
end
