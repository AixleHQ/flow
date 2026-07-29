# frozen_string_literal: true

# Serialized as the shared `currentUser` prop (and the Profile page's
# `profile` prop). The multi-company fields depend on the REQUEST's current
# membership, which controllers pass via Alba params:
#
#   CurrentUserResource.new(user, params: { current_membership: }).to_h
#
# Without that param `current_company`/`current_role` degrade to nil
# (super admins still get "super_admin" — they have no memberships).
class CurrentUserResource < ApplicationResource
  attributes :id, :email, :name, :state, :created_at, :updated_at

  # Credentials, agents and every onboarding answer belong to the CURRENT
  # MEMBERSHIP, not the user: a person authenticates a separate agent account per
  # company so vendor spend is billed to the company that incurred it.
  typelize "AgentCredential[]"
  attribute :agent_credentials do |_user|
    (params[:current_membership]&.credentials || []).map { |c| AgentCredentialResource.new(c).to_h }
  end

  typelize :string?
  attribute :position do |_user|
    params[:current_membership]&.position&.to_s
  end

  typelize :string?
  attribute :preferred_agent_language do |_user|
    params[:current_membership]&.preferred_agent_language
  end

  typelize "string[]"
  attribute :selected_agents do |_user|
    params[:current_membership]&.selected_agents || []
  end

  typelize :string
  attribute :onboarding_state do |user|
    # Super admins never onboard; report them complete so no guard bounces them.
    next "completed" if user.super_admin?

    params[:current_membership]&.onboarding_state || "step1"
  end

  typelize :string?
  attribute :onboarding_completed_at do |_user|
    params[:current_membership]&.onboarding_completed_at
  end

  typelize "number | null"
  attribute :default_agent_credential_id do |_user|
    params[:current_membership]&.default_agent_credential_id
  end

  typelize "Company | null"
  attribute :current_company do |user|
    # current_membership is an element of user.active_memberships, and Alba
    # serializes attributes in declaration order — so :company has to be
    # preloaded here, before this reads it, not only in :memberships below.
    user.active_memberships_with_company
    company = params[:current_membership]&.company
    company && CompanyResource.new(company).to_h
  end

  typelize "'employee' | 'admin' | 'viewer' | 'super_admin' | null"
  attribute :current_role do |user|
    next "super_admin" if user.super_admin?

    params[:current_membership]&.role&.to_s
  end

  typelize "Membership[]"
  attribute :memberships do |user|
    # Memoized on the User instance — this resource renders on EVERY request
    # (InertiaRails.always) and the policy predicates share the same load. The
    # company preload happens on first dereference, so predicate-only callers
    # never eager-load an association they don't touch.
    user.active_memberships_with_company.map { |m| MembershipResource.new(m).to_h }
  end

  typelize "string[]"
  attribute :configured_agents do |_user|
    params[:current_membership]&.configured_agents || []
  end

  typelize :string?
  attribute :default_agent_runtime do |_user|
    params[:current_membership]&.default_agent_runtime
  end

  # Drives the "connect an agent" nudge: onboarding skipped the agent step for a
  # viewer who has since been given a role that can actually run things.
  typelize :boolean
  attribute :needs_agent_setup do |_user|
    params[:current_membership]&.needs_agent_setup? || false
  end
end
