# frozen_string_literal: true

module Web
  module Company
    class SwitchPolicy < ApplicationPolicy
      # Any signed-in member may attempt a switch; the controller validates the
      # target company against the user's active memberships.
      def create? = true
    end
  end
end
