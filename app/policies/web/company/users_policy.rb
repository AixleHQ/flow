# frozen_string_literal: true

module Web
  module Company
    # The organization-visible member profile is a read every member of the
    # company gets, viewers included — seeing that a teammate's CLI plan is
    # spent is the point of the page, and gating it on a role would leave the
    # people who most often notice a dead bot unable to diagnose it.
    #
    # WHICH member is readable is a scoping question, not a role question: the
    # controller's company-scoped lookup 404s anyone outside the current
    # company, so there is nothing for a role gate to add here.
    class UsersPolicy < ApplicationPolicy
      def show?
        true
      end
    end
  end
end
