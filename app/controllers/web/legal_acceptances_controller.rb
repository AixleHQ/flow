# frozen_string_literal: true

# Where enforce_legal_acceptance sends someone who has not accepted the current
# Terms of Use, or an admin whose company has not accepted the current Terms of
# Service. Each document is accepted on its own, at the version the page showed.
class Web::LegalAcceptancesController < Web::ApplicationController
  layout "inertia"

  STALE = "These terms were updated while you were reading them. Please review the current versions."
  INCOMPLETE = "Accept each document to continue."

  skip_before_action :enforce_legal_acceptance
  skip_before_action :enforce_onboarding
  before_action :require_signed_in

  def show
    return redirect_to(company_projects_path) if impersonated? || pending_legal_documents.empty?

    render inertia: "Legal/AcceptPage", props: {
      company_name: current_company.branded_name,
      documents: pending_legal_documents.map { |document| document_props(document) }
    }
  end

  def create
    return redirect_to(company_projects_path) if impersonated?

    pending = pending_legal_documents
    accepted = accepted_versions(pending)
    refusal = refusal_for(pending, accepted)
    return redirect_to(legal_acceptance_path, inertia: { errors: { base: refusal } }) if refusal

    LegalAcceptance.transaction do
      pending.each do |document|
        LegalAcceptance.record!(document, user: current_user, company: current_company, request: request)
      end
    end
    redirect_to company_projects_path
  end

  private

  def require_signed_in
    redirect_to login_path unless signed_in?
  end

  def accepted_versions(pending)
    given = params[:accepted]
    given.is_a?(ActionController::Parameters) ? given.permit(*pending.map(&:key)).to_h : {}
  end

  # A version that is not the current one means the person ticked a box for text
  # that has since changed, which is not an acceptance of what is in force now.
  def refusal_for(pending, accepted)
    return STALE if accepted.any? { |key, version| version != LegalDocument.find(key).version }

    INCOMPLETE if pending.any? { |document| accepted[document.key].blank? }
  end

  def document_props(document)
    {
      key: document.key,
      title: document.title,
      version: document.version,
      updated_on: document.updated_on.iso8601,
      accepted_by: document.accepted_by.to_s,
      url: public_send(:"legal_#{document.key}_path")
    }
  end
end
