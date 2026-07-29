# frozen_string_literal: true

# A members-page row serialized from a CompanyMembership: global identity
# fields come from the user, per-company role/state/invitation data from the
# membership itself. `id` is the USER id — member routes are keyed by user_id.
class MemberResource < ApplicationResource
  # No `Member` model exists — resolve DB column types (invited_at/accepted_at)
  # from CompanyMembership so Typelizer doesn't emit `unknown`.
  typelize_from CompanyMembership

  attributes :invited_at, :accepted_at

  typelize :number
  attribute :id, &:user_id

  typelize :string
  attribute :email do |membership|
    membership.user.email
  end

  typelize :string
  attribute :name do |membership|
    membership.user.name
  end

  typelize :string
  attribute :role do |membership|
    membership.role.to_s
  end

  typelize :string
  attribute :state do |membership|
    membership.state.to_s
  end

  typelize :string?
  attribute :position do |membership|
    # Per company: the same person can hold a different position in each.
    membership.position&.to_s
  end

  typelize :string
  attribute :created_at do |membership|
    membership.user.created_at
  end

  typelize "{ id: number; name: string } | null"
  attribute :invited_by do |membership|
    next nil if membership.invited_by.blank?

    { id: membership.invited_by.id, name: membership.invited_by.name }
  end
end
