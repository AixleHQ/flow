# frozen_string_literal: true

require "test_helper"

# Version history is complete only if every writer of a versioned entity goes
# through Versions (docs/design/entity-versioning.md §5.2) — it is written
# explicitly, never by a callback. A new personal tool or controller that writes
# one of the five types directly would silently punch a hole in the history;
# this fails instead.
class Versions::WritePathCoverageTest < ActiveSupport::TestCase
  VERSIONED_NOUNS = /\A(create|update|delete|install|uninstall|duplicate|reorder)_(agent|skill|custom_tool|mcp_server|
                     connector|workflow|workflow_step|workflow_steps|sub_step|sub_steps)\z/x
  # Writers that hand an actor to a service which records the version itself,
  # or wrap the write in the workflows API's `versioned` helper.
  DELEGATES = /Versions\.|actor: version_actor|versioned \{/

  CONTROLLERS = %w[
    app/controllers/web/company/projects/agents_controller.rb
    app/controllers/web/company/projects/skills_controller.rb
    app/controllers/web/company/projects/tools_controller.rb
    app/controllers/web/company/projects/mcp_servers_controller.rb
    app/controllers/web/company/projects/connectors_controller.rb
    app/controllers/web/company/projects/workflows_controller.rb
    app/controllers/web/company/workflow_catalog_controller.rb
    app/controllers/api/v1/projects/workflows_controller.rb
    app/controllers/api/v1/projects/workflows/steps_controller.rb
    app/controllers/api/v1/projects/workflows/aggregates_controller.rb
  ].freeze

  test "every personal tool that writes a versioned entity records a version" do
    writers = Dir[Rails.root.join("app/services/personal_tools/*.rb")].select do |path|
      VERSIONED_NOUNS.match?(File.basename(path, ".rb"))
    end
    assert_operator writers.size, :>=, 20, "the tool naming convention changed; update VERSIONED_NOUNS"

    missing = writers.reject { |path| File.read(path).match?(DELEGATES) }
    assert_empty missing.map { |p| p.delete_prefix("#{Rails.root}/") }, "these tools write without Versions"
  end

  test "every controller that writes a versioned entity records a version" do
    missing = CONTROLLERS.reject { |path| Rails.root.join(path).read.match?(DELEGATES) }
    assert_empty missing, "these controllers write without Versions"
  end
end
