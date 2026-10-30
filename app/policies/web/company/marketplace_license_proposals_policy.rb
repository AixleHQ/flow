# frozen_string_literal: true

module Web
  module Company
    # Answering a request to bill this workspace through AWS Marketplace.
    # The same answer as the Billing tab's own controls, and for the same
    # reason: this moves who pays for the workspace.
    class MarketplaceLicenseProposalsPolicy < ApplicationPolicy
      def create? = admin?
      def destroy? = admin?
    end
  end
end
