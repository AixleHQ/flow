# frozen_string_literal: true

require "test_helper"

# Deleting a company is what the admin's delete button does, and every table
# that points at `companies` decides whether it still can. Two added on the
# Marketplace branch did not, which no test noticed because nothing else here
# deletes one.
class CompanyDeletionTest < ActiveSupport::TestCase
  test "a company whose billing state has ever changed can still be deleted" do
    company = create(:company, billing_state: "trialing")
    company.update!(billing_state: "blocked", billing_block_reason: "allowance")

    assert_operator CompanyBillingStateChange.where(company_id: company.id).count, :>, 0,
                    "the log has to hold a row for this to be the case under test"

    company.destroy!

    assert_not Company.exists?(company.id)
    assert_empty CompanyBillingStateChange.where(company_id: company.id),
                 "the log is worth exactly as much as the company it describes"
  end

  test "a company a subscription was offered to can still be deleted, and the licence outlives it" do
    company = create(:company)
    license = create(:marketplace_license, :active, proposed_company: company, proposal_state: "pending")

    company.destroy!

    assert_not Company.exists?(company.id)
    assert_nil license.reload.proposed_company_id,
               "the offer lapses with the company; the subscription does not"
  end

  test "a company with a SCIM endpoint can still be deleted, and its credential goes with it" do
    company = create(:company)
    scim = ScimConfiguration.create!(company: company, token_digest: ScimConfiguration.digest("ascim_token"))

    company.destroy!

    assert_not Company.exists?(company.id)
    assert_not ScimConfiguration.exists?(scim.id)
  end

  test "every table that points at companies lets one go" do
    cleared = Company.reflect_on_all_associations.filter_map do |association|
      next if association.through_reflection?
      next unless %i[destroy delete delete_all nullify].include?(association.options[:dependent])

      [ association.klass.table_name, association.foreign_key.to_s ]
    end
    connection = ActiveRecord::Base.connection

    blocking = connection.tables.flat_map { |table| connection.foreign_keys(table) }
                         .select { |fk| fk.to_table == "companies" }
                         .reject { |fk| %i[cascade nullify].include?(fk.on_delete) }
                         .reject { |fk| cleared.include?([ fk.from_table, fk.column ]) }
                         .map { |fk| "#{fk.from_table}.#{fk.column}" }

    assert_empty blocking,
                 "deleting a company fails on these foreign keys: give each an on_delete, " \
                 "or a `dependent:` association on Company"
  end
end
