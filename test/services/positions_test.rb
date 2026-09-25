# frozen_string_literal: true

require "test_helper"

class PositionsTest < ActiveSupport::TestCase
  setup do
    user = create(:user, :with_company)
    @workflow = create(:workflow, scope: create(:project, company: user.companies.first, owner: user))
    @a = @workflow.steps.create!(name: "A", position: 1)
    @b = @workflow.steps.create!(name: "B", position: 2)
    @c = @workflow.steps.create!(name: "C", position: 3)
  end

  test "the named rows take the first positions in the order given" do
    Positions.reorder!(@workflow.steps, [ @c.id, @a.id, @b.id ])

    assert_equal %w[C A B], @workflow.steps.reorder(:position).pluck(:name)
  end

  # Renumbering only the named rows put C on 1 while A still held it.
  test "rows left out of the list follow, in their current order" do
    Positions.reorder!(@workflow.steps, [ @c.id ])

    assert_equal [ [ "C", 1 ], [ "A", 2 ], [ "B", 3 ] ], @workflow.steps.reorder(:position).pluck(:name, :position)
  end

  # A soft-deleted step keeps its slot in the (workflow_id, position) unique index.
  test "a soft-deleted row keeps a slot and never collides" do
    @b.update_columns(deleted_at: Time.current)

    Positions.reorder!(@workflow.steps, [ @c.id, @a.id ])

    assert_equal [ [ "C", 1 ], [ "A", 2 ] ], @workflow.steps.not_deleted.reorder(:position).pluck(:name, :position)
    assert_equal 3, @b.reload.position
  end

  test "ids that are unknown or repeated are ignored" do
    Positions.reorder!(@workflow.steps, [ @b.id, @b.id, 999_999 ])

    assert_equal %w[B A C], @workflow.steps.reorder(:position).pluck(:name)
  end
end
