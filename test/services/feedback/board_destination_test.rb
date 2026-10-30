# frozen_string_literal: true

require "test_helper"

class Feedback::BoardDestinationTest < ActiveSupport::TestCase
  setup do
    freeze_time
    # The operator's project, in a company of its own: feedback crosses companies.
    @project = project
    @board = create(:board, project: @project)
    create(:board_column, board: @board, name: "Backlog")
    @column = create(:board_column, board: @board, name: "Feedback")
    configure(board_project_id: @project.id, board_column_id: @column.id)

    sender_company = create(:company, name: "Acme | Corp")
    @user = create(:user, company: sender_company, name: "Jane Doe")
    @submission = create(:feedback_submission, company: sender_company, user: @user, kind: "bug",
                                               message: "\n  Board is blank after archiving a column\nSteps: archive, reload",
                                               page_url: "https://flow.example.com/company/projects/7/board",
                                               app_version: "1.8.0")
  end

  def project
    company = create(:company)
    create(:project, company: company, owner: create(:user, company: company))
  end

  def configure(**settings)
    Settings.stubs(:feedback).returns(Hashie::Mash.new(settings))
  end

  def deliver = Feedback::BoardDestination.new(@submission).deliver

  test "makes the submission a card in the configured column" do
    deliver

    card = @column.board_tasks.sole
    assert_equal "Bug: Board is blank after archiving a column", card.title
    assert_equal "bug", card.task_type
    assert_equal %w[feedback bug], card.tags
    assert_equal <<~MARKDOWN.chomp, card.description
      #{@submission.message}

      | | |
      | --- | --- |
      | **Type** | Bug |
      | **From** | Jane Doe (#{@user.email}) |
      | **Company** | Acme \\| Corp |
      | **Page** | https://flow.example.com/company/projects/7/board |
      | **Version** | 1.8.0 |
      | **Sent** | #{Time.current.utc.strftime('%Y-%m-%d %H:%M UTC')} |
    MARKDOWN
    assert_equal Time.current, @submission.reload.board_delivered_at
  end

  test "a request that is not a bug is not typed as one" do
    @submission.update!(kind: "feature_request")

    deliver

    card = @column.board_tasks.sole
    assert_equal "not_specified", card.task_type
    assert_equal %w[feedback feature-request], card.tags
  end

  test "attaches a copy of each file to the card, and lists them" do
    @submission.attach([ Rack::Test::UploadedFile.new(StringIO.new("PNG bytes"), "image/png", original_filename: "board.png") ])
    @submission.save!

    deliver

    card = @column.board_tasks.sole
    asset = card.task_assets.sole
    assert_equal [ "board.png", "system", "PNG bytes" ], [ asset.name, asset.author_type, asset.file.read ]
    assert_not_equal @submission.attachments.sole.file.id, asset.file.id, "the card keeps a file of its own"
    assert_includes card.description, "| **Files** | board.png |"
  end

  test "makes one card however often it is delivered" do
    deliver
    deliver

    assert_equal 1, @board.board_tasks.count
  end

  test "refuses a column that is not on the configured project's board" do
    other_column = create(:board_column, board: create(:board, project: project))
    configure(board_project_id: @project.id, board_column_id: other_column.id)

    assert_raises(Feedback::DeliveryRejected) { deliver }
    assert_equal 0, BoardTask.count
    assert_nil @submission.reload.board_delivered_at
  end
end
