# frozen_string_literal: true

require "test_helper"

class WorkspaceOnboardingFormTest < ActiveSupport::TestCase
  setup { @user = create(:user, email: "dana@acme-robotics.example") }

  def form(**attrs)
    WorkspaceOnboardingForm.new(
      user: @user,
      **{ name: "Acme Robotics", email_domain: "acme-robotics.example", max_sessions: 5 }.merge(attrs)
    )
  end

  test "creates the company, an admin membership and the limit together" do
    built = form
    assert built.save, built.errors.full_messages.to_sentence

    company = built.company
    assert_equal "Acme Robotics", company.name
    assert_equal "admin", @user.company_memberships.find_by(company: company).role
    assert_equal 5, SessionConcurrencyLimit.for_company(company.id)
  end

  # The whole reason this rule lives here: a company made anywhere else may have
  # no limit, and one that signs itself up may not.
  test "a limit is required" do
    built = form(max_sessions: nil)

    assert_not built.save
    assert_includes built.errors[:max_sessions].to_sentence, "is not a number"
  end

  test "zero is not a limit" do
    assert_not form(max_sessions: 0).save
  end

  test "a name is required" do
    assert_not form(name: " ").save
  end

  # Otherwise anyone could claim a domain they have no address at, and every
  # later sign-in from it would auto-join the workspace they built.
  test "the domain must be the one they signed in with" do
    built = form(email_domain: "someone-else.example")

    assert_not built.save
    assert_includes built.errors[:email_domain].to_sentence, "your own email address"
  end

  test "a domain that already has a workspace is refused" do
    create(:company, email_domain: "acme-robotics.example")

    built = form

    assert_not built.save
    assert_includes built.errors[:email_domain].to_sentence, "already has a workspace"
  end

  test "the domain defaults to the address they signed in with" do
    assert_equal "acme-robotics.example", WorkspaceOnboardingForm.new(user: @user).email_domain
  end

  test "a refused save leaves nothing behind" do
    assert_no_difference [ "Company.count", "CompanyMembership.count", "SessionConcurrencyLimit.count" ] do
      form(max_sessions: 0).save
    end
  end

  # Company's own rules still apply; the form reports them rather than raising.
  test "a company validation surfaces as a form error" do
    built = form(email_domain: "admin.com")

    assert_not built.save
    assert_not_empty built.errors
  end
end
