# frozen_string_literal: true

require "test_helper"

# Web::Company::ApplicationController refuses a viewer's writes before any action
# runs, whatever the action's policy says. A controller opts out only for writes
# that are the actor's own business; this list is the whole set of them.
class Web::Company::ReadOnlyBackstopTest < ActiveSupport::TestCase
  VIEWER_WRITABLE = %w[
    Web::Company::MembershipsController
    Web::Company::Projects::FavoritesController
    Web::Company::SwitchController
  ].freeze

  test "every company controller but the personal ones refuses a viewer's writes" do
    Rails.application.eager_load!

    opted_out = Web::Company::ApplicationController.descendants.reject do |controller|
      controller._process_action_callbacks.any? { |callback| callback.filter == :deny_read_only_mutation! }
    end

    assert_equal VIEWER_WRITABLE, opted_out.map(&:name).sort
  end
end
