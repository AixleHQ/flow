# frozen_string_literal: true

require "test_helper"

class CompanyPublicIdTest < ActiveSupport::TestCase
  test "every company has its own public id" do
    first = create(:company)
    second = create(:company)

    assert_match(/\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/, first.public_id)
    assert_not_equal first.public_id, second.public_id
  end

  # Customers pin it in a federated credential in their own Entra app.
  test "cannot be rewritten" do
    company = create(:company)
    original = company.public_id

    assert_raises(ActiveRecord::ReadonlyAttributeError) { company.update!(public_id: SecureRandom.uuid) }
    assert_equal original, company.reload.public_id
  end

  test "does not follow the company's name or slug" do
    company = create(:company)
    original = company.public_id

    company.update!(name: "Renamed #{SecureRandom.hex(3)}", slug: "renamed-#{SecureRandom.hex(3)}")

    assert_equal original, company.reload.public_id
  end
end
