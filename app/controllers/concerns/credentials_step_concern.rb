# frozen_string_literal: true

# Step two of signing in: the same login screen, told which address it is for
# and which methods the workspace that domain resolves to actually accepts — or,
# for a domain no workspace claims, what the installation offers.
#
# Shared because two controllers reach it — #identify when an address has no
# connection to be sent to, and #create when a password is refused.
# A refusal that redirected to /login would land on step ONE, making the person
# retype the address they had already given.
module CredentialsStepConcern
  extend ActiveSupport::Concern

  private

  def render_credentials_step(email, options, errors: {})
    render inertia: "Auth/LoginPage", props: {
      step: "credentials",
      email: email,
      # Nil for an unclaimed domain. Naming the workspace its member belongs to
      # would tell anyone who typed the address where that person works.
      company_name: options.company&.branded_name,
      # Intersected with what this INSTALLATION offers, so a company policy can
      # never conjure a method the deployment has no credentials for (AD-4).
      methods: options.kinds & Auth::PolicyResolver.deployment_allowlist_kinds,
      dead_end: options.dead_end?,
      # The step cannot tell a member from someone about to sign their company
      # up, so where signup is open it offers both.
      can_create_workspace: options.unclaimed? && Deployment.self_serve_signup?,
      errors: errors
    }
  end
end
