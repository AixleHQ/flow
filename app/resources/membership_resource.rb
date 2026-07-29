# frozen_string_literal: true

# A user's OWN membership row (Profile "Companies" card, sidebar company
# switcher). Distinct from MemberResource, which is a members-page row keyed
# by user_id — here `id` is the MEMBERSHIP id (the leave-company route uses it).
class MembershipResource < ApplicationResource
  typelize_from CompanyMembership

  attributes :id

  typelize %w[employee admin viewer]
  attribute :role do |membership|
    membership.role.to_s
  end

  typelize :string
  attribute :state do |membership|
    membership.state.to_s
  end

  one :company, resource: CompanyResource
end
