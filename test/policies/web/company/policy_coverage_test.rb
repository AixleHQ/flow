# frozen_string_literal: true

require "test_helper"

# Every company-scoped Web controller runs `dynamic_authorize!`, which sends
# `#{action}?` to the controller's policy. A method that is not there does not
# deny the request — it raises NoMethodError, so the endpoint 500s for everyone,
# including the people who were allowed. That is how `update_connector` reached
# production.
#
# Actions are added far more often than policies are re-read, so the pairing is
# checked here rather than remembered. This is a structural test: it asserts the
# policy can answer, not what it answers — the permit/forbid matrices in
# test/policies and the per-controller authorization tests own that.
class Web::Company::PolicyCoverageTest < ActiveSupport::TestCase
  # Actions that deliberately run without a policy, each by an explicit
  # `skip_before_action :dynamic_authorize!`. The list is the review surface:
  # adding to it means "this endpoint authorizes itself", and it should stay
  # small enough to read.
  SELF_AUTHORIZING = {
    # The GitHub App setup URL is one fixed app-wide value, so the callback
    # lands here for every project and authorizes itself from the signed
    # `state` param instead of from a company membership.
    "Web::Company::Integrations::GithubSetupController" => %w[github_setup]
  }.freeze

  test "every company-scoped action has a policy method to answer it" do
    routes = company_routes
    # A structural sweep that stops finding anything passes silently forever, so
    # the sweep itself is asserted. The number is a floor, not the count.
    assert_operator routes.size, :>, 50, "the route sweep found almost nothing — has the base class moved?"

    gaps = routes.filter_map do |controller_name, action|
      controller = controller_name.safe_constantize
      next if controller.nil?
      next if SELF_AUTHORIZING.fetch(controller_name, []).include?(action)

      policy = policy_for(controller_name)
      next "#{controller_name} has no policy class" if policy.nil?
      next if policy.method_defined?(:"#{action}?") || policy.private_method_defined?(:"#{action}?")

      "#{policy}##{action}? is missing (#{controller_name}##{action})"
    end

    assert_empty gaps, "Actions reachable without a policy method:\n  #{gaps.join("\n  ")}"
  end

  private

  # The controller/action pairs Rails will actually route to, for controllers
  # that inherit the company-scoped authorization chain.
  def company_routes
    Rails.application.routes.routes.filter_map do |route|
      controller = route.defaults[:controller]
      action = route.defaults[:action]
      next if controller.blank? || action.blank?

      name = "#{controller}_controller".camelize
      klass = name.safe_constantize
      next unless klass.respond_to?(:ancestors) && klass < Web::Company::ApplicationController

      [ name, action ]
    end.uniq
  end

  # Resolved exactly the way AuthorizationConcern resolves it at request time:
  # the controller's namespace becomes the symbol array handed to Pundit.
  def policy_for(controller_name)
    subject = controller_name.gsub(/Controller/, "").split("::").map { |part| part.underscore.downcase.to_sym }
    Pundit::PolicyFinder.new(subject).policy
  end
end
