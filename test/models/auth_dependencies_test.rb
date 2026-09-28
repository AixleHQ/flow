# frozen_string_literal: true

require "test_helper"

# The one dependency rule this application will not drift on.
class AuthDependenciesTest < ActiveSupport::TestCase
  test "no SAML parser is ever linked into this process" do
    # `ruby-saml` — the only Ruby SAML service provider, and what every wrapper
    # (omniauth-saml, devise_saml_authenticatable) sits on — has had five
    # Critical authentication-bypass advisories in fifteen months, in three
    # rounds, each a new angle on the same hazard: two XML parsers, one document,
    # one trust decision. December 2025's fix was published as an incomplete fix
    # of March's.
    #
    # Enterprise SSO here is per-company OIDC, which every identity provider
    # that matters speaks — Entra, Okta, Ping, OneLogin, Google Workspace. If
    # SAML is ever genuinely required, adding it must be a deliberate decision
    # taken with this history in front of whoever takes it, which is what this
    # test forces.
    lock = Rails.root.join("Gemfile.lock").read

    refute_match(/^\s+ruby-saml /, lock)
    refute_match(/^\s+omniauth-saml /, lock)
    refute_match(/^\s+devise_saml_authenticatable /, lock)
  end
end
