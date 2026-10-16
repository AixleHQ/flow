# frozen_string_literal: true

require "test_helper"

class DecodesHtmlEntitiesTest < ActiveSupport::TestCase
  test "a label an agent wrote HTML-escaped is stored as plain text" do
    workflow = create(:workflow, name: "QA &amp; Merge")
    step = create(:step, workflow: workflow, name: "Plan &amp; release next batch")
    sub_step = create(:sub_step, step: step, name: "Reconcile &lt;plan&gt; &quot;vs&quot; board &#39;n&#39; code")
    board = Board.create!(name: "Board", project: workflow.scope)
    column = BoardColumn.create!(name: "Backlog", board: board, position: 1)
    task = BoardTask.create!(title: "History &amp; settlement detail", board: board, board_column: column)

    assert_equal "QA & Merge", workflow.reload.name
    assert_equal "Plan & release next batch", step.reload.name
    assert_equal %(Reconcile <plan> "vs" board 'n' code), sub_step.reload.name
    assert_equal "History & settlement detail", task.reload.title
  end

  test "a plain ampersand and the markdown instructions are left as written" do
    step = create(:step, name: "Review diff & route", instructions: "Escape `<` as `&lt;` in the email body.")

    step.update!(name: "Merge into staging & deploy")

    assert_equal "Merge into staging & deploy", step.reload.name
    assert_equal "Escape `<` as `&lt;` in the email body.", step.instructions
  end
end
