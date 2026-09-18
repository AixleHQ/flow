# frozen_string_literal: true

module Web
  module Company
    class SettingsPolicy < Web::Company::ApplicationPolicy
      def show? = true
      def update? = admin?

      # Branding and who joins the company are ordinary company administration.
      # How many sessions the company may run at once is not: in the hosted
      # product it is the number we invoice for, so it moves from the platform
      # admin and nowhere else. A self-hosted customer buys their own capacity
      # and may set it themselves.
      def manage_capacity? = admin? && Deployment.self_hosted?
    end
  end
end
