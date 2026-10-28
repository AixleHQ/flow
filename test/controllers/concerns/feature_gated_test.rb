# frozen_string_literal: true

require "test_helper"

# `requires_feature` (FeatureGated): a 404 while the flag is off, scoped to the
# actions it names, a company-scoped flag read for the current company and left
# to authentication when nobody is signed in. The runners request tests cover
# it on real controllers.
class FeatureGatedTest < ActionDispatch::IntegrationTest
  class GatedController < ActionController::Base
    include FeatureGated

    requires_feature :external_runners
    requires_feature :coder_reap, only: :reaping

    def index = head(:ok)
    def reaping = head(:ok)

    private

    # Stand-ins for AuthConcern: the test names the company in a header.
    def signed_in? = request.headers["X-Company-Id"].present?
    def current_company = Company.find(request.headers["X-Company-Id"])
  end

  setup { @company = create(:company) }

  def draw_gated_routes(&)
    with_routing do |set|
      set.draw do
        get "gated", to: "feature_gated_test/gated#index"
        get "gated/reaping", to: "feature_gated_test/gated#reaping"
      end
      yield
    end
  end

  def get_as_company(path, company = @company) = get(path, headers: { "X-Company-Id" => company.id.to_s })

  test "a company-scoped flag is read for the current company" do
    other = create(:company)
    with_feature(:external_runners, true, company: @company) do
      draw_gated_routes do
        get_as_company "/gated"
        assert_response :ok
        get_as_company "/gated", other
        assert_response :not_found
      end
    end
  end

  test "an anonymous request is left to authentication rather than answered 404" do
    with_feature(:external_runners, false) do
      draw_gated_routes do
        get "/gated"
        assert_response :ok
      end
    end
  end

  test "only: limits a flag to the actions it names, and a global flag ignores the company" do
    with_feature(:external_runners, true, company: @company) do
      with_feature(:coder_reap, false) do
        draw_gated_routes do
          get_as_company "/gated"
          assert_response :ok
          get_as_company "/gated/reaping"
          assert_response :not_found
        end
      end
      with_feature(:coder_reap, true) do
        draw_gated_routes do
          get_as_company "/gated/reaping"
          assert_response :ok
        end
      end
    end
  end
end
