# frozen_string_literal: true

# The published legal documents. Public, and readable while /legal/accept is
# holding someone back, because that page links here.
class Web::LegalController < Web::ApplicationController
  layout "web/legal"

  skip_before_action :enforce_workspace
  skip_before_action :enforce_company_auth_policy
  skip_before_action :enforce_legal_acceptance
  skip_before_action :enforce_onboarding
  skip_before_action :redirect_super_admin_to_admin_panel
  before_action :require_published

  def index
    @documents = LegalDocument::ALL
  end

  def privacy_policy = show(LegalDocument::PRIVACY_POLICY)
  def terms_of_service = show(LegalDocument::TERMS_OF_SERVICE)
  def terms_of_use = show(LegalDocument::TERMS_OF_USE)

  private

  def show(document)
    @document = document
    render document.key
  end

  def require_published
    head :not_found unless LegalDocument.published?
  end
end
