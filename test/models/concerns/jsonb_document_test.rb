# frozen_string_literal: true

require "test_helper"

class JsonbDocumentTest < ActiveSupport::TestCase
  setup do
    user = create(:user, :with_company)
    project = create(:project, company: user.companies.first, owner: user)
    @session = create(:terminal_session, :agent_session, user: user, project: project, metadata: { "a" => 1 })
    # Another process's copy of the same row, loaded before anyone writes.
    @stale = TerminalSession.find(@session.id)
  end

  test "merge keeps a key another writer stored after this copy was read" do
    @session.merge_jsonb!(:metadata, "b" => 2)

    @stale.merge_jsonb!(:metadata, "c" => 3)

    assert_equal({ "a" => 1, "b" => 2, "c" => 3 }, @session.reload.metadata)
    assert_equal({ "a" => 1, "b" => 2, "c" => 3 }, @stale.metadata)
    assert_not @stale.changed?
  end

  test "merge removes only the keys it names" do
    @session.merge_jsonb!(:metadata, "b" => 2)

    @stale.remove_jsonb_keys!(:metadata, "a")

    assert_equal({ "b" => 2 }, @session.reload.metadata)
  end

  test "merge starts a document that was never written" do
    @session.update_column(:metadata, nil)

    @session.merge_jsonb!(:metadata, "x" => [ 1, 2 ])

    assert_equal({ "x" => [ 1, 2 ] }, @session.reload.metadata)
  end

  test "a computed change starts from the stored document, not this copy's" do
    @session.change_jsonb!(:metadata) { |doc| (doc["list"] ||= []) << "first" }

    @stale.change_jsonb!(:metadata) { |doc| (doc["list"] ||= []) << "second" }

    assert_equal %w[first second], @session.reload.metadata["list"]
    assert_equal 1, @session.metadata["a"]
  end

  test "a computed change saved with callbacks goes through the model" do
    @stale.change_jsonb!(:metadata, callbacks: true) { |doc| doc["b"] = 2 }

    assert_equal({ "a" => 1, "b" => 2 }, @session.reload.metadata)
    assert_operator @session.updated_at, :>=, @stale.created_at
  end

  test "refuses a column that is not jsonb" do
    assert_raises(ArgumentError) { @session.merge_jsonb!(:state, "x" => 1) }
  end
end
