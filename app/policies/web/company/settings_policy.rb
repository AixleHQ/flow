# frozen_string_literal: true

module Web
  module Company
    class SettingsPolicy < Web::Company::ApplicationPolicy
      def show? = true
      def update? = admin?

      # Branding and who joins the company are ordinary company administration.
      # How many sessions the company may run at once is not: where we invoice
      # for that number it moves from the platform admin and nowhere else. A
      # customer who buys their own capacity — self-hosted, or through AWS
      # Marketplace — sets it themselves.
      def manage_capacity? = admin? && Deployment.customer_owns_capacity?
    end
  end
end
