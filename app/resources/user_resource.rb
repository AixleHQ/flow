# frozen_string_literal: true

class UserResource < ApplicationResource
  attributes :id, :email, :name, :state, :created_at, :updated_at

  # Position is per-company too (a person can be qa in one company and cto in
  # another), so it resolves through the same `params: { company: }` context as
  # the role below.
  typelize :string?
  attribute :position do |user|
    company = params[:company]
    next nil unless company

    user.company_memberships.find { |m| m.company_id == company.id }&.position&.to_s
  end

  # Roles are per-company (CompanyMembership); pass `params: { company: }` to
  # resolve the user's role within that company. Without a company context the
  # role is nil (a user has no global role anymore).
  typelize :string?
  attribute :role do |user|
    company = params[:company]
    next nil unless company

    user.company_memberships.find { |m| m.company_id == company.id }&.role&.to_s
  end
end
