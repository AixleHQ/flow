# frozen_string_literal: true

require "test_helper"

class OutputValidatorTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @user = create(:user, company: @company)
    @project = create(:project, company: @company, owner: @user)
    @workflow = create(:workflow, scope: @company)
    @workflow_run = create(:workflow_run, workflow: @workflow, project: @project, user: @user)
  end

  def markdown_asset(content, **attrs)
    asset = create(:workflow_run_asset, { content_type: "text/markdown", workflow_run: @workflow_run }.merge(attrs))
    asset.file = WorkflowRunAssetUploader.upload(StringIO.new(content), :store)
    asset.save!
    asset
  end

  test "no output specs is valid regardless of collected assets" do
    step = create(:step, workflow: @workflow, output_asset_specs: [])

    result = OutputValidator.new(step, []).validate!

    assert result.valid?, result.errors.to_sentence
    assert_equal [], result.errors
  end

  test "required output present by exact name is valid" do
    step = create(:step, workflow: @workflow, output_asset_specs: [ { "name" => "report.md" } ])
    asset = create(:workflow_run_asset, workflow_run: @workflow_run, name: "report.md")

    result = OutputValidator.new(step, [ asset ]).validate!

    assert result.valid?, result.errors.to_sentence
    assert_equal [], result.errors
  end

  test "required output present by name_pattern regex is valid" do
    step = create(:step, workflow: @workflow, output_asset_specs: [ { "name_pattern" => 'report-.*\.md' } ])
    asset = create(:workflow_run_asset, workflow_run: @workflow_run, name: "report-final.md")

    result = OutputValidator.new(step, [ asset ]).validate!

    assert result.valid?, result.errors.to_sentence
    assert_equal [], result.errors
  end

  test "optional output missing is valid" do
    step = create(:step, workflow: @workflow, output_asset_specs: [ { "name" => "optional.md", "required" => false } ])

    result = OutputValidator.new(step, []).validate!

    assert result.valid?, result.errors.to_sentence
    assert_equal [], result.errors
  end

  test "asset meeting min_size is valid" do
    step = create(:step, workflow: @workflow, output_asset_specs: [ { "name" => "big.md", "min_size" => 500 } ])
    asset = create(:workflow_run_asset, workflow_run: @workflow_run, name: "big.md", file_size: 1024)

    result = OutputValidator.new(step, [ asset ]).validate!

    assert result.valid?, result.errors.to_sentence
    assert_equal [], result.errors
  end

  test "markdown asset containing all required sections is valid" do
    step = create(:step, workflow: @workflow, output_asset_specs: [
      { "name" => "doc.md", "required_sections" => [ "Summary", "Results" ] }
    ])
    asset = markdown_asset(
      "# Summary\n\nIntro text.\n\n## Results\n\nThe findings.\n",
      name: "doc.md"
    )

    result = OutputValidator.new(step, [ asset ]).validate!

    assert result.valid?, result.errors.to_sentence
    assert_equal [], result.errors
  end

  test "section matching is case-insensitive" do
    step = create(:step, workflow: @workflow, output_asset_specs: [
      { "name" => "doc.md", "required_sections" => [ "summary" ] }
    ])
    asset = markdown_asset("# SUMMARY\n\nBody.\n", name: "doc.md")

    result = OutputValidator.new(step, [ asset ]).validate!

    assert result.valid?, result.errors.to_sentence
    assert_equal [], result.errors
  end

  test "multiple specs all satisfied is valid" do
    step = create(:step, workflow: @workflow, output_asset_specs: [
      { "name" => "report.md", "min_size" => 100 },
      { "name_pattern" => 'data-\d+\.csv' },
      { "name" => "notes.md", "required" => false }
    ])
    report = create(:workflow_run_asset, workflow_run: @workflow_run, name: "report.md", file_size: 2048)
    data = create(:workflow_run_asset, workflow_run: @workflow_run, name: "data-42.csv", content_type: "text/csv")

    result = OutputValidator.new(step, [ report, data ]).validate!

    assert result.valid?, result.errors.to_sentence
    assert_equal [], result.errors
  end

  test "name_pattern matching several assets validates each of them" do
    step = create(:step, workflow: @workflow, output_asset_specs: [
      { "name_pattern" => 'chapter-\d+\.md', "min_size" => 10 }
    ])
    ch1 = create(:workflow_run_asset, workflow_run: @workflow_run, name: "chapter-1.md", file_size: 100)
    ch2 = create(:workflow_run_asset, workflow_run: @workflow_run, name: "chapter-2.md", file_size: 200)

    result = OutputValidator.new(step, [ ch1, ch2 ]).validate!

    assert result.valid?, result.errors.to_sentence
    assert_equal [], result.errors
  end
end
