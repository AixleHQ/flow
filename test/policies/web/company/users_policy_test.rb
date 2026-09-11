# frozen_string_literal: true

require "test_helper"

# The organization-visible member profile is a read for every member of the
# company. Seeing that a teammate's CLI plan is spent is the point of the page,
# so a viewer — often the person who notices a dead bot first — gets the same
# answer an admin does. Which member is readable is scoping, not policy; the
# controller owns that (see Web::Company::UsersControllerTest).
class Web::Company::UsersPolicyTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
  end

  def policy_for(user)
    Web::Company::UsersPolicy.new(BaseContext.new(user, ActionController::Parameters.new, company: @company), nil)
  end

  test "show? is true for every role in the company" do
    %i[admin employee viewer].each do |role|
      # Viewers are external clients — their email domain must NOT match the
      # company (the domain validation skips read-only users).
      attrs = { company: @company }
      attrs[:email] = "client-#{SecureRandom.hex(3)}@external.com" if role == :viewer
      user = create(:user, role, :onboarding_completed, **attrs)

      assert policy_for(user).show?, "#{role} should be able to read a member profile"
    end
  end

  test "show? does not depend on having a membership at all — scoping denies, not the policy" do
    outsider = create(:user, :employee, :onboarding_completed, company: create(:company))

    assert policy_for(outsider).show?
  end
end
