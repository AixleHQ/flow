# frozen_string_literal: true

module Web
  module Company
    class SettingsPolicy < Web::Company::ApplicationPolicy
      def show? = true
      def update? = admin?

      # A company admin sets how many sessions their own company may run, in
      # every deployment: raising it raises what they are charged for, so the
      # number costs them what it gives them. What they may never do is clear it
      # — see the controller — because a company with no limit is one nobody is
      # invoiced for, and that is ours to grant, not theirs to take.
      def manage_capacity? = admin?
    end
  end
end
