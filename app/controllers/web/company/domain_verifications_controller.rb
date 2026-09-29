# frozen_string_literal: true

# Checking whether the DNS record is there yet.
#
# A write, not a read, because it is what turns domain auto-join on: until this
# succeeds a workspace takes members by invitation alone.
class Web::Company::DomainVerificationsController < Web::Company::ApplicationController
  def create
    if Domains::Verification.verify!(current_company)
      redirect_to company_settings_access_path,
                  notice: "#{current_company.email_domain} is verified. People signing in from it now join this workspace."
    else
      refuse("We could not find that record at #{Domains::Verification.host_for(current_company)} yet. " \
             "DNS can take a few minutes to publish — try again shortly.")
    end
  end

  private

  def refuse(message)
    redirect_to company_settings_access_path, inertia: { errors: { base: message } }
  end
end
