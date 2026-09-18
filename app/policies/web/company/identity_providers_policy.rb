# frozen_string_literal: true

module Web
  module Company
    # Connecting a company's identity provider is an administrative act: it
    # decides who can become a member of this company.
    class IdentityProvidersPolicy < ApplicationPolicy
      def create? = admin?
      def update? = admin?
      def destroy? = admin?
    end
  end
end
