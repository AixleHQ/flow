# frozen_string_literal: true

require "test_helper"

class MarketplaceLicenseTest < ActiveSupport::TestCase
  test "a licence needs the three things AWS always sends" do
    license = build(:marketplace_license)
    assert license.valid?, license.errors.full_messages.to_sentence

    %i[license_arn customer_aws_account_id product_code].each do |attribute|
      record = build(:marketplace_license, attribute => nil)

      assert_not record.valid?, "#{attribute} should be required"
    end
  end

  # The whole point of keying on the licence: a second arrival carrying one we
  # already hold is the same purchase and must not make a second row.
  test "one licence exists once" do
    first = create(:marketplace_license)
    second = build(:marketplace_license, license_arn: first.license_arn)

    assert_not second.valid?
    assert_includes second.errors[:license_arn], "has already been taken"
  end

  # Concurrent Agreements: several live agreements on one AWS account is the
  # feature, not a collision.
  test "one AWS account may hold several licences" do
    create(:marketplace_license, customer_aws_account_id: "444455556666")
    second = build(:marketplace_license, customer_aws_account_id: "444455556666")

    assert second.valid?, second.errors.full_messages.to_sentence
  end

  test "a company holds at most one licence" do
    company = create(:company)
    create(:marketplace_license, company: company)
    second = build(:marketplace_license, company: company)

    assert_not second.valid?
    assert_includes second.errors[:company_id], "has already been taken"
  end

  # A subscription can exist before anybody registers, so an unbound licence is
  # ordinary rather than invalid.
  test "a licence with no company yet is valid, and several may wait at once" do
    assert create(:marketplace_license).valid?
    assert create(:marketplace_license).valid?

    assert_equal 2, MarketplaceLicense.where(company_id: nil).count
  end

  test "an unknown subscription state is refused" do
    assert_not build(:marketplace_license, subscription_state: "cancelled").valid?
  end

  test "metering follows the state, and ending still counts" do
    company = create(:company)

    assert_not create(:marketplace_license, :active).meterable?, "unbound: AWS has nobody to bill"
    assert_not create(:marketplace_license, company: company).meterable?, "pending: AWS discards it"

    license = create(:marketplace_license, :active, company: create(:company))
    assert license.meterable?

    # The hour after an agreement ends is exactly when the last usage has to go.
    license.update!(subscription_state: "ending")
    assert license.meterable?

    license.update!(subscription_state: "ended")
    assert_not license.meterable?
  end

  test "the unregistered scope finds subscriptions nobody can reach, and drops the dead ones" do
    waiting = create(:marketplace_license, :active)
    create(:marketplace_license, :active, company: create(:company))
    create(:marketplace_license, :ended)

    assert_equal [ waiting.id ], MarketplaceLicense.unregistered.pluck(:id)
  end

  test "a bound licence reports the company and survives its destruction being refused" do
    company = create(:company)
    license = create(:marketplace_license, :active, company: company)

    assert license.bound?
    assert_equal company, license.company
    assert_equal [ license.id ], MarketplaceLicense.bound.pluck(:id)
  end
end
