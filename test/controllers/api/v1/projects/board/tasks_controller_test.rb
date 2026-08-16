# frozen_string_literal: true

require "test_helper"

module Api
  module V1
  module Projects
    module Board
      class TasksControllerTest < ActionController::TestCase
        setup do
          @company = create(:company)
          @user = create(:user, :onboarding_completed, company: @company)
          @project = create(:project, company: @company, owner: @user)
          @board = create(:board, project: @project)
          @col1 = create(:board_column, board: @board, name: "Todo")
          @col2 = create(:board_column, board: @board, name: "Done")
          @task = create(:board_task, board: @board, board_column: @col1)
          @workflow = create(:workflow, scope: @project)
          sign_in @user
        end

        test "index returns tasks json" do
          get :index, params: { project_id: @project.id }

          assert_response :success
        end

        test "index pages one column and reports its unpaginated total" do
          create_list(:board_task, 3, board: @board, board_column: @col1)
          create(:board_task, board: @board, board_column: @col2)

          get :index, params: { project_id: @project.id, board_column_id: @col1.id, limit: 2, offset: 0 }

          assert_response :success
          body = JSON.parse(response.body)
          assert_equal 2, body.length
          # @task plus the three above; the header is what lets the column header show a real total
          # while holding one page.
          assert_equal "4", response.headers["X-Total-Count"]
          assert(body.all? { |t| t["boardColumnId"] == @col1.id })
        end

        test "index pages in board order without repeating a task across pages" do
          tasks = 3.times.map { |i| create(:board_task, board: @board, board_column: @col2, position: i) }

          get :index, params: { project_id: @project.id, board_column_id: @col2.id, limit: 2, offset: 0 }
          first_page = JSON.parse(response.body).map { |t| t["id"] }
          get :index, params: { project_id: @project.id, board_column_id: @col2.id, limit: 2, offset: 2 }
          second_page = JSON.parse(response.body).map { |t| t["id"] }

          assert_equal tasks.map(&:id), first_page + second_page
        end

        test "index filters by the ransack predicates the board sends" do
          assignee = @user
          match = create(:board_task, board: @board, board_column: @col1, title: "Fix login crash",
            task_type: :bug, priority: :high, assignee: assignee)
          create(:board_task, board: @board, board_column: @col1, title: "Build settings page", task_type: :story)

          get :index, params: {
            project_id: @project.id,
            q: { title_cont: "login", task_type_eq: "bug", priority_eq: "high", assignee_id_eq: assignee.id }
          }

          assert_response :success
          assert_equal [ match.id ], JSON.parse(response.body).map { |t| t["id"] }
          assert_equal "1", response.headers["X-Total-Count"]
        end

        test "index tags_match=all requires every tag, while the default still matches any" do
          both = create(:board_task, board: @board, board_column: @col1, tags: %w[api ui])
          one = create(:board_task, board: @board, board_column: @col1, tags: %w[api])

          get :index, params: { project_id: @project.id, tags: %w[api ui], tags_match: "all" }
          assert_equal [ both.id ], JSON.parse(response.body).map { |t| t["id"] }

          get :index, params: { project_id: @project.id, tags: %w[api ui] }
          assert_equal [ both.id, one.id ].sort, JSON.parse(response.body).map { |t| t["id"] }.sort
        end

        test "index archived=all returns active and archived tasks together" do
          archived = create(:board_task, board: @board, board_column: @col1, archived_at: Time.current)

          get :index, params: { project_id: @project.id, archived: "all" }

          ids = JSON.parse(response.body).map { |t| t["id"] }
          assert_includes ids, archived.id
          assert_includes ids, @task.id
          assert_equal "2", response.headers["X-Total-Count"]
        end

        test "show returns task json" do
          get :show, params: { project_id: @project.id, id: @task.id }

          assert_response :success
        end

        test "create returns task json" do
          post :create, params: {
            project_id: @project.id,
            board_task: { title: "New task", board_column_id: @col1.id }
          }

          assert_response :created
        end

        test "create attaches the new task to an epic" do
          epic = create(:board_task, board: @board, board_column: @col1, task_type: :epic)

          post :create, params: {
            project_id: @project.id,
            board_task: { title: "Child story", board_column_id: @col1.id, task_type: "story", parent_task_id: epic.id }
          }

          assert_response :created
          assert_equal epic.id, JSON.parse(response.body)["parentTaskId"]
          assert_equal epic.id, BoardTask.find_by(title: "Child story").parent_task_id
        end

        test "create with a non-epic parent returns unprocessable entity" do
          non_epic = create(:board_task, board: @board, board_column: @col1, task_type: :bug)

          post :create, params: {
            project_id: @project.id,
            board_task: { title: "Child story", board_column_id: @col1.id, parent_task_id: non_epic.id }
          }

          assert_response :unprocessable_entity
          assert_nil BoardTask.find_by(title: "Child story")
        end

        test "update returns task json" do
          patch :update, params: {
            project_id: @project.id,
            id: @task.id,
            board_task: { title: "Updated" }
          }

          assert_response :success
        end

        test "update assigns a valid epic parent" do
          epic = create(:board_task, board: @board, board_column: @col1, task_type: :epic)

          patch :update, params: {
            project_id: @project.id,
            id: @task.id,
            board_task: { parent_task_id: epic.id }
          }

          assert_response :success
          assert_equal epic.id, @task.reload.parent_task_id
        end

        test "update with invalid parent returns unprocessable entity instead of silently succeeding" do
          non_epic = create(:board_task, board: @board, board_column: @col1, task_type: :bug)

          patch :update, params: {
            project_id: @project.id,
            id: @task.id,
            board_task: { parent_task_id: non_epic.id }
          }

          assert_response :unprocessable_entity
          assert_nil @task.reload.parent_task_id
          assert JSON.parse(response.body)["errors"].present?
        end

        test "destroy removes task" do
          delete :destroy, params: { project_id: @project.id, id: @task.id }

          assert_response :no_content
        end

        test "move returns task json" do
          patch :move, params: {
            project_id: @project.id,
            id: @task.id,
            column_id: @col2.id
          }

          assert_response :success
        end

        test "archive marks the task archived" do
          patch :archive, params: { project_id: @project.id, id: @task.id }

          assert_response :success
          assert_predicate @task.reload, :archived?
        end

        test "unarchive restores an archived task" do
          @task.update!(archived_at: Time.current)

          patch :unarchive, params: { project_id: @project.id, id: @task.id }

          assert_response :success
          assert_not @task.reload.archived?
        end

        test "index excludes archived tasks by default" do
          archived = create(:board_task, board: @board, board_column: @col1, archived_at: Time.current)

          get :index, params: { project_id: @project.id }

          assert_response :success
          ids = JSON.parse(response.body).map { |t| t["id"] }
          assert_includes ids, @task.id
          assert_not_includes ids, archived.id
        end

        test "index with archived filter returns only archived tasks" do
          archived = create(:board_task, board: @board, board_column: @col1, archived_at: Time.current)

          get :index, params: { project_id: @project.id, archived: "archived" }

          assert_response :success
          ids = JSON.parse(response.body).map { |t| t["id"] }
          assert_includes ids, archived.id
          assert_not_includes ids, @task.id
        end

        test "index supports limit and offset for on-demand loading" do
          create_list(:board_task, 3, board: @board, board_column: @col2)

          get :index, params: { project_id: @project.id, board_column_id: @col2.id, limit: 2, offset: 1 }

          assert_response :success
          assert_equal 2, JSON.parse(response.body).length
        end

        test "workflow_runs returns runs json" do
          create(:workflow_run, workflow: @workflow, project: @project, user: @user, board_task: @task)

          get :workflow_runs, params: { project_id: @project.id, id: @task.id }

          assert_response :success
        end

        test "trigger_workflow returns run json when service succeeds" do
          ColumnWorkflowBinding.create!(
            board_column: @col1,
            workflow: @workflow,
            trigger_mode: :manual,
            cooldown_seconds: 0
          )
          run = create(:workflow_run, :running, workflow: @workflow, project: @project, user: @user, board_task: @task)
          TaskService.stubs(:trigger_workflow).returns(run)

          post :trigger_workflow, params: { project_id: @project.id, id: @task.id }

          assert_response :success
        end

        # The button authorizes the clicker but the run belongs to the assignee —
        # run.user is what the container spends, and the work on the card is
        # theirs. See TaskService#run_owner_for.
        test "trigger_workflow starts the run under the task's assignee, not the caller" do
          assignee = create(:user, :onboarding_completed, company: @company)
          @project.add_collaborator(assignee)
          # Eligible to own a run only with an agent credential in this company —
          # see TaskService#can_own_runs?.
          create(:agent_credential, user: assignee, company: @company)
          @task.update!(assignee: assignee)
          ColumnWorkflowBinding.create!(
            board_column: @col1, workflow: @workflow, trigger_mode: :manual, cooldown_seconds: 0
          )
          WorkflowService.expects(:start).with(has_entries(user: assignee))
                         .returns(create(:workflow_run, workflow: @workflow, project: @project, user: assignee))

          post :trigger_workflow, params: { project_id: @project.id, id: @task.id }

          assert_response :success
        end

        # The board card's column selector calls #move, so this guards the path the
        # UI actually uses.
        test "move into an auto-bound column starts that column's workflow" do
          ColumnWorkflowBinding.create!(board_column: @col2, workflow: @workflow, trigger_mode: :auto, cooldown_seconds: 0)
          WorkflowService.expects(:start).once.returns(create(:workflow_run, workflow: @workflow, project: @project, user: @user))

          patch :move, params: { project_id: @project.id, id: @task.id, column_id: @col2.id }

          assert_response :success
          assert_equal @col2.id, @task.reload.board_column_id
        end

        # Regression: board_column_id is a permitted attribute here, so a plain
        # PATCH used to relocate the card while skipping the transition record,
        # the task_moved activity and the column's auto-trigger entirely.
        test "update that changes the column moves the task, exactly as #move would" do
          ColumnWorkflowBinding.create!(board_column: @col2, workflow: @workflow, trigger_mode: :auto, cooldown_seconds: 0)
          WorkflowService.expects(:start).once.returns(create(:workflow_run, workflow: @workflow, project: @project, user: @user))

          assert_difference -> { ColumnTransition.count }, 1 do
            patch :update, params: {
              project_id: @project.id, id: @task.id,
              board_task: { board_column_id: @col2.id }
            }
          end

          assert_response :success
          assert_equal @col2.id, @task.reload.board_column_id
        end

        # === viewer (read-only) enforcement ===

        class ViewerTest < ActionController::TestCase
          tests Api::V1::Projects::Board::TasksController

          setup do
            @company = create(:company)
            @owner = create(:user, :onboarding_completed, company: @company)
            @project = create(:project, company: @company, owner: @owner)
            @board = create(:board, project: @project)
            @col1 = create(:board_column, board: @board, name: "Todo")
            @col2 = create(:board_column, board: @board, name: "Done")
            @task = create(:board_task, board: @board, board_column: @col1)
            @viewer = create(:user, :viewer, company: @company, email: "client@ext.com")
            @project.add_collaborator(@viewer)
            sign_in @viewer
          end

          test "viewer can read index/show/workflow_runs" do
            get :index, params: { project_id: @project.id }
            assert_response :success
            get :show, params: { project_id: @project.id, id: @task.id }
            assert_response :success
            get :workflow_runs, params: { project_id: @project.id, id: @task.id }
            assert_response :success
          end

          test "viewer create is forbidden" do
            post :create, params: { project_id: @project.id, board_task: { title: "X", board_column_id: @col1.id } }
            assert_response :forbidden
          end

          test "viewer update is forbidden" do
            patch :update, params: { project_id: @project.id, id: @task.id, board_task: { title: "Y" } }
            assert_response :forbidden
          end

          test "viewer destroy is forbidden" do
            delete :destroy, params: { project_id: @project.id, id: @task.id }
            assert_response :forbidden
          end

          test "viewer move is forbidden" do
            patch :move, params: { project_id: @project.id, id: @task.id, column_id: @col2.id }
            assert_response :forbidden
          end

          test "viewer archive is forbidden" do
            patch :archive, params: { project_id: @project.id, id: @task.id }
            assert_response :forbidden
          end

          test "viewer unarchive is forbidden" do
            patch :unarchive, params: { project_id: @project.id, id: @task.id }
            assert_response :forbidden
          end

          test "viewer trigger_workflow is forbidden" do
            post :trigger_workflow, params: { project_id: @project.id, id: @task.id }
            assert_response :forbidden
          end
        end
      end
    end
  end
  end
end
