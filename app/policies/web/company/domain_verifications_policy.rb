# frozen_string_literal: true

module Web
  module Company
    # Same door as the rest of the Access tab: proving the domain is what lets
    # strangers from it into the workspace, so it is an administrator's to do.
    class DomainVerificationsPolicy < ApplicationPolicy
      def create? = admin?
    end
  end
end
