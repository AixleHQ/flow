# frozen_string_literal: true

require "test_helper"

class InsightsUsageExportTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @user = create(:user, :employee, company: @company)
    @session = create(:terminal_session, user: @user, company_id: @company.id)
  end

  test "state is validated against STATES" do
    export = build(:insights_usage_export, terminal_session: @session, state: "bogus")
    assert { !export.valid? }
    assert { export.errors[:state].present? }

    InsightsUsageExport::STATES.each do |state|
      valid = build(:insights_usage_export, terminal_session: @session, state: state)
      assert { valid.valid? }
    end
  end

  test "a second row for the same session is rejected by the unique index" do
    create(:insights_usage_export, terminal_session: @session)

    duplicate = build(:insights_usage_export, terminal_session: @session)
    assert_raises(ActiveRecord::RecordNotUnique) { duplicate.save! }
  end

  test "exported! sets state/records_sent/exported_at and clears error" do
    export = create(:insights_usage_export, terminal_session: @session, error: "earlier failure")

    freeze_time do
      export.exported!(5)

      assert { export.state == "exported" }
      assert { export.records_sent == 5 }
      assert { export.error.nil? }
      assert { export.exported_at == Time.current }
    end
  end

  test "failed! sets state/error truncated to 1000 chars and increments attempts" do
    export = create(:insights_usage_export, terminal_session: @session, attempts: 2)

    export.failed!("x" * 1500)

    assert { export.state == "failed" }
    assert { export.error.length == 1000 }
    assert { export.attempts == 3 }
  end

  test "skipped! sets state" do
    export = create(:insights_usage_export, terminal_session: @session)

    export.skipped!

    assert { export.state == "skipped" }
  end

  test "unsent returns pending and failed rows only" do
    pending_row = create(:insights_usage_export, terminal_session: @session, state: "pending")
    failed_row = create(:insights_usage_export, terminal_session: another_session, state: "failed")
    create(:insights_usage_export, terminal_session: another_session, state: "exported")
    create(:insights_usage_export, terminal_session: another_session, state: "skipped")

    assert { InsightsUsageExport.unsent.to_set == [ pending_row, failed_row ].to_set }
  end

  test "REPLAY_WINDOW mirrors the Insights 7-day attribution window" do
    assert { InsightsUsageExport::REPLAY_WINDOW == 7.days }
  end

  test "for_company scopes to rows with that company_id and a nil company still saves" do
    company = @session.company
    mine = create(:insights_usage_export, terminal_session: @session, company: company)
    other_session = another_session
    create(:insights_usage_export, terminal_session: other_session, company: other_session.company)

    assert { InsightsUsageExport.for_company(company).to_a == [ mine ] }

    orphan = create(:insights_usage_export, terminal_session: another_session, company: nil)
    assert { orphan.persisted? }
    assert { orphan.company.nil? }
  end

  private

  # A terminal session on its own company, so each ledger row is for a distinct
  # session (the unique index) and the per-company scope has rows to exclude.
  def another_session
    company = create(:company)
    user = create(:user, :employee, company: company)
    create(:terminal_session, user: user, company_id: company.id)
  end
end
