# frozen_string_literal: true

module Web
  module Company
    # Issuing a directory-sync credential decides who can be added to this
    # company in bulk, which is an administrative act.
    class ScimConfigurationsPolicy < ApplicationPolicy
      def create? = admin?
      def destroy? = admin?
    end
  end
end
