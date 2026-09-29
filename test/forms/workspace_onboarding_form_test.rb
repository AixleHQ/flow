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

  # A stranger's form: no account yet, and the address is whatever they typed.
  def stranger(**attrs)
    WorkspaceOnboardingForm.new(
      **{ name: "Acme Robotics", email: "dana@northwind.example", max_sessions: 5 }.merge(attrs)
    )
  end

  test "creates the company, an admin membership and the limit together" do
    built = form
    assert built.save(@user), built.errors.full_messages.to_sentence

    company = built.company
    assert_equal "Acme Robotics", company.name
    assert_equal "admin", @user.company_memberships.find_by(company: company).role
    assert_equal 5, SessionConcurrencyLimit.for_company(company.id)
  end

  # The whole reason this rule lives here: a company made anywhere else may have
  # no limit, and one that signs itself up may not.
  test "a limit is required" do
    built = form(max_sessions: nil)

    assert_not built.save(@user)
    assert_includes built.errors[:max_sessions].to_sentence, "is not a number"
  end

  test "zero is not a limit" do
    assert_not form(max_sessions: 0).save(@user)
  end

  test "a name is required" do
    assert_not form(name: " ").save(@user)
  end

  # Otherwise anyone could claim a domain they have no address at, and every
  # later sign-in from it would auto-join the workspace they built.
  test "the domain must be the one the address is at" do
    built = form(email_domain: "someone-else.example")

    assert_not built.save(@user)
    assert_includes built.errors[:email_domain].to_sentence, "your own email address"
  end

  test "a domain that already has a workspace is refused" do
    create(:company, email_domain: "acme-robotics.example")

    built = form

    assert_not built.save(@user)
    assert_includes built.errors[:email_domain].to_sentence, "already has a workspace"
  end

  test "the domain defaults to the address they signed in with" do
    assert_equal "acme-robotics.example", WorkspaceOnboardingForm.new(user: @user).email_domain
  end

  # Someone signed in does not get to name an address: theirs is the one they
  # proved, whatever the form body says.
  test "a signed-in person cannot sign up as somebody else" do
    built = form(email: "attacker@evil.example")

    assert_equal "dana@acme-robotics.example", built.email
  end

  test "a refused save leaves nothing behind" do
    assert_no_difference [ "Company.count", "CompanyMembership.count", "SessionConcurrencyLimit.count" ] do
      form(max_sessions: 0).save(@user)
    end
  end

  # Company's own rules still apply; the form reports them rather than raising.
  test "a company validation surfaces as a form error" do
    built = form(email_domain: "admin.com")

    assert_not built.save(@user)
    assert_not_empty built.errors
  end

  # ── A stranger, whose account does not exist yet ───────────────────────────

  test "the domain comes from the address a stranger typed" do
    assert_equal "northwind.example", stranger.email_domain
  end

  test "an address is required when nobody is signed in" do
    built = stranger(email: nil)

    assert_not built.valid?
    assert_includes built.errors[:email].to_sentence, "blank"
  end

  test "something that is not an address is refused" do
    built = stranger(email: "dana at northwind")

    assert_not built.valid?
    assert_includes built.errors[:email].to_sentence, "is not an email address"
  end

  # The free allowance belongs to this path alone. A company made in the admin is
  # somebody deciding, and one that stopped after a hundred queue-hours because a
  # column defaulted that way would be a surprise nobody would connect to this.
  test "a company that signs itself up starts on the free allowance" do
    built = stranger
    built.save(built.owner_for(nil))

    assert built.company.billing_trialing?
  end

  test "a company made any other way does not" do
    assert create(:company).billing_active?
    assert Company.new.billing_active?, "the column default is what an operator means"
  end

  test "it creates the account along with the workspace" do
    built = stranger

    assert_difference "User.count", 1 do
      assert built.save(built.owner_for(nil)), built.errors.full_messages.to_sentence
    end

    owner = User.find_by(email: "dana@northwind.example")
    assert_equal "admin", owner.company_memberships.find_by(company: built.company).role
  end

  # A person who already has an account but no workspace signs up as themselves,
  # rather than colliding on email uniqueness.
  test "an existing account owns the workspace rather than a second one" do
    existing = create(:user, email: "dana@northwind.example")
    built = stranger

    assert_no_difference "User.count" do
      assert built.save(built.owner_for(existing)), built.errors.full_messages.to_sentence
    end
    assert_equal existing, built.company.company_memberships.first.user
  end

  # The account is written inside the same transaction as the company, so a
  # signup that fails on the last step does not leave a stray person behind.
  test "a refused save leaves no account behind either" do
    built = stranger(max_sessions: 0)

    assert_no_difference "User.count" do
      assert_not built.save(built.owner_for(nil))
    end
  end

  # Claiming a domain takes it from everyone else at it, and at a public service
  # that is everyone. The first Gmail signup would own Gmail.
  test "a public mail service cannot be claimed" do
    built = stranger(email: "dana@gmail.com")

    assert_not built.valid?
    assert_includes built.errors[:email_domain].to_sentence, "public email service"
  end

  test "the same goes for someone already signed in" do
    user = create(:user, email: "dana@yandex.ru")
    built = WorkspaceOnboardingForm.new(user: user, name: "Acme", max_sessions: 5)

    assert_not built.valid?
    assert_includes built.errors[:email_domain].to_sentence, "public email service"
  end

  test "an organisation's own domain is not a public mail service" do
    assert stranger(email: "dana@northwind.example").valid?
  end

  test "it names the account from the address" do
    assert_equal "Dana", stranger.name_from_email
    assert_equal "Dana Scully", stranger(email: "dana.scully@northwind.example").name_from_email
  end
end
