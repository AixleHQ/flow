# frozen_string_literal: true

class BaseContext
  attr_reader :user, :params, :company

  def initialize(user, params, company: nil)
    @user = user
    @params = params
    @company = company
  end

  # The user's active membership in the context company (nil when the context
  # has no company, e.g. company-less API calls, or when the user is not an
  # active member — policies must fail closed on nil).
  def membership
    return @membership if defined?(@membership)

    # Through User#active_memberships (memoized per instance) so a request that
    # builds several policy contexts issues one membership query, not one each.
    @membership = user && company ? user.active_memberships.find { |m| m.company_id == company.id } : nil
  end
end
