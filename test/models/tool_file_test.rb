# frozen_string_literal: true

require "test_helper"

class ToolFileTest < ActiveSupport::TestCase
  setup do
    user = create(:user, :with_company)
    @tool = create(:tool, scope: create(:project, company: user.companies.first, owner: user))
  end

  test "two files with the same name in different folders are two objects" do
    first = @tool.tool_files.create!(path: "/workspace/a/config.json", file: StringIO.new("A"))
    second = @tool.tool_files.create!(path: "/workspace/b/config.json", file: StringIO.new("B"))

    assert_not_equal first.file.id, second.file.id
    assert_equal "A", first.reload.file.download.read
    assert_equal "B", second.reload.file.download.read
  end

  test "replacing a file keeps the new bytes" do
    tool_file = @tool.tool_files.create!(path: "/workspace/run.sh", file: StringIO.new("old"))

    tool_file.update!(file: StringIO.new("new"))

    assert_equal "new", tool_file.reload.file.download.read
  end

  test "text content posted with CRLF newlines is stored with LF" do
    tool_file = @tool.tool_files.create!(path: "/workspace/run.sh", content: "#!/bin/sh\r\necho hi\r\n")

    assert_equal "#!/bin/sh\necho hi\n", tool_file.reload.content
  end
end
