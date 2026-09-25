# frozen_string_literal: true

require "test_helper"

class Versions::ToolSnapshotTest < ActiveSupport::TestCase
  setup do
    @company = create(:company)
    @user = create(:user, company: @company)
    @project = create(:project, company: @company, owner: @user)
    @actor = Versions::Actor.ui(@user)
    @tool = create(:tool, scope: @project, command: "run v1")
  end

  test "revert restores text and binary files, and the stored object of a removed file survives" do
    @tool.tool_files.create!(path: "/workspace/config.json", content: "{\"v\":1}")
    binary = @tool.tool_files.create!(path: "/workspace/data.bin", file: StringIO.new("bytes v1"))
    Versions.save!(@tool, actor: @actor) { @tool.update!(description: "v1") }
    v1 = @tool.latest_version

    Versions.save!(@tool, actor: @actor) do
      @tool.update!(command: "run v2", tool_files_attributes: [ { id: binary.id, _destroy: "1" } ])
      @tool.tool_files.find_by(path: "/workspace/config.json").update!(content: "{\"v\":2}")
    end

    Versions.revert!(@tool, to: v1, actor: @actor)

    files = @tool.reload.tool_files.index_by(&:path)
    assert_equal "run v1", @tool.command
    assert_equal "{\"v\":1}", files["/workspace/config.json"].content
    assert_equal "bytes v1", files["/workspace/data.bin"].file.download.read
  end

  test "a reverted tool keeps an intact definition digest, so it is still served" do
    Versions.save!(@tool, actor: @actor) { @tool.update!(description: "first") }
    first = @tool.latest_version
    Versions.save!(@tool, actor: @actor) { @tool.update!(command: "run v2", input_schema: { "type" => "object" }) }

    Versions.revert!(@tool, to: first, actor: @actor)

    assert @tool.reload.definition_digest_intact?
    assert_equal "run v1", @tool.command
  end
end
