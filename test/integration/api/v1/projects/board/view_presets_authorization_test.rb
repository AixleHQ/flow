# frozen_string_literal: true

require "test_helper"

# Request-level authorization matrix for the API board view-presets endpoints, via
# the shared AuthorizationMatrix harness (docs/testing.md §2).
#
# Policy (Api::V1::Projects::Board::ViewPresetsPolicy < Web::…::ViewPresetsPolicy):
#   index?             => project_accessible?  (read)
#   create? / destroy? => project_writable?    (write)
#     project_writable? == project_accessible? && !current_user.read_only?
#   so owner/admin/employee-collaborator may mutate; the read-only viewer may read
#   but not write; strangers / foreign admins are scoped out of the project.
#
# current_project resolves via Project.for_user(current_user).find(:project_id), so
# an inaccessible project raises RecordNotFound (404) BEFORE the policy — that is
# why strangers / foreign admins get 404, not 403. current_board is current_project
# .board (else RecordNotFound), and a project has no auto-created board, so the
# board is built in setup.
#
# destroy has an in-action ownership guard (`preset.user_id == current_user.id`
# else 403) that runs AFTER the policy, so each allowed role deletes a self-owned
# throwaway preset to reach a clean :no_content (proving the policy permitted the
# write). There is no BoardViewPreset factory and `filters` has a presence
# validation, so presets are built directly with a non-empty filters hash.
class Api::V1::Projects::Board::ViewPresetsAuthorizationTest < ActionDispatch::IntegrationTest
  include AuthorizationMatrix

  setup do
    setup_project_authz_personas
    @board = create(:board, project: @project)
  end

  teardown { teardown_authz }

  test "index is a project read" do
    assert_project_read(transport: :api) { get api_v1_project_view_presets_path(@project) }
  end

  test "create is a project write" do
    assert_project_write(transport: :api) do
      post api_v1_project_view_presets_path(@project),
           params: { board_view_preset: { name: "Preset via API", filters: { status: "open" } } }, as: :json
    end
  end

  # destroy mutates and has a self-ownership guard after the policy, so each allowed
  # role deletes its own throwaway preset. Denied/scoped-out roles never reach it.
  test "destroy is a project write" do
    assert_project_write(transport: :api) do |role|
      preset = BoardViewPreset.create!(board: @board, user: user_for(role),
                                       name: "Disposable #{role}", filters: { "status" => "done" })
      delete api_v1_project_view_preset_path(@project, preset)
    end
  end
end
