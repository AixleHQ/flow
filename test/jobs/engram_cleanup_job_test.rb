# frozen_string_literal: true

require "test_helper"

class EngramCleanupJobTest < ActiveJob::TestCase
  test "destroying an indexed memory queues scoped cleanup" do
    project = create(:project, :standalone)
    memory = ProjectMemory.create!(project: project, title: "Finding", content: "Brief", topic_key: "finding", engram_id: "42")
    namespace = "flow:company:#{project.company_id}:project:#{project.id}"

    assert_enqueued_with(job: EngramCleanupJob, args: [ "42", namespace ]) { memory.destroy! }
  end

  test "cleanup deletes only the expected projection and is safe to repeat" do
    client = FakeEngramClient.new
    id = client.save(project: "owned", title: "Finding", content: "Brief", topic_key: "finding")
    Engram::Client.stubs(:build).returns(client)

    2.times { EngramCleanupJob.perform_now(id, "owned") }
    assert_equal [], client.search(project: "owned", query: "Finding", limit: 3)
  end
end
