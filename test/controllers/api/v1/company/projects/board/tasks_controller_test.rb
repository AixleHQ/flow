# frozen_string_literal: true

require "test_helper"

class Api::V1::Company::Projects::Board::TasksControllerTest < ActionController::TestCase
  setup do
    @company = create(:company, email_domain: "testcompany.com")
    @owner = create(:user, :employee, company: @company)
    @collaborator = create(:user, :employee, company: @company)
    @other_user = create(:user, :employee, company: @company)

    @project = create(:project, company: @company, owner: @owner)
    @project.add_collaborator(@collaborator)

    @board = Board.create!(name: "Dev Board", project: @project)
    @col1 = BoardColumn.create!(name: "Backlog", board: @board, position: 1)
    @col2 = BoardColumn.create!(name: "Done", board: @board, position: 2)

    @task = BoardTask.create!(title: "Existing Task", board: @board, board_column: @col1)
  end

  # ====== INDEX Tests ======

  test "#index returns all tasks" do
    sign_in @owner

    get :index, params: { project_id: @project.id }

    assert_response :success
    json = response.parsed_body
    assert_equal 1, json["items"].length
  end

  test "#index filters by board_column_id" do
    BoardTask.create!(title: "Done Task", board: @board, board_column: @col2)
    sign_in @owner

    get :index, params: { project_id: @project.id, board_column_id: @col2.id }

    assert_response :success
    json = response.parsed_body
    assert_equal 1, json["items"].length
    assert_equal "Done Task", json["items"].first["title"]
  end

  test "#index filters by assignee_id via ransack" do
    BoardTask.create!(title: "Assigned", board: @board, board_column: @col1, assignee: @owner)
    sign_in @owner

    get :index, params: { project_id: @project.id, q: { assignee_id_eq: @owner.id } }

    assert_response :success
    json = response.parsed_body
    assert_equal 1, json["items"].length
    assert_equal "Assigned", json["items"].first["title"]
  end

  test "#index filters by task_type via ransack" do
    BoardTask.create!(title: "Bug", board: @board, board_column: @col1, task_type: :bug)
    sign_in @owner

    get :index, params: { project_id: @project.id, q: { task_type_eq: "bug" } }

    assert_response :success
    json = response.parsed_body
    assert_equal 1, json["items"].length
    assert_equal "Bug", json["items"].first["title"]
  end

  test "#index searches by title via ransack" do
    BoardTask.create!(title: "Login API", board: @board, board_column: @col1)
    sign_in @owner

    get :index, params: { project_id: @project.id, q: { title_cont: "Login" } }

    assert_response :success
    json = response.parsed_body
    assert_equal 1, json["items"].length
    assert_equal "Login API", json["items"].first["title"]
  end

  test "#index filters by tags overlap" do
    BoardTask.create!(title: "Tagged", board: @board, board_column: @col1, tags: %w[urgent frontend])
    BoardTask.create!(title: "Other", board: @board, board_column: @col1, tags: %w[backend])
    sign_in @owner

    get :index, params: { project_id: @project.id, tags: %w[frontend] }

    assert_response :success
    json = response.parsed_body
    assert_equal 1, json["items"].length
    assert_equal "Tagged", json["items"].first["title"]
  end

  test "#index filters by parent_task_id via ransack" do
    epic = BoardTask.create!(title: "Epic", board: @board, board_column: @col1, task_type: :epic)
    BoardTask.create!(title: "Story", board: @board, board_column: @col1, parent_task: epic)
    sign_in @owner

    get :index, params: { project_id: @project.id, q: { parent_task_id_eq: epic.id } }

    assert_response :success
    json = response.parsed_body
    assert_equal 1, json["items"].length
    assert_equal "Story", json["items"].first["title"]
  end

  test "#index accessible by collaborator" do
    sign_in @collaborator

    get :index, params: { project_id: @project.id }

    assert_response :success
  end

  test "#index not accessible by non-member" do
    sign_in @other_user

    get :index, params: { project_id: @project.id }

    assert_response :forbidden
  end

  # ====== SHOW Tests ======

  test "#show returns single task" do
    sign_in @owner

    get :show, params: { project_id: @project.id, id: @task.id }

    assert_response :success
    json = response.parsed_body
    assert_equal "Existing Task", json["data"]["title"]
    assert_equal 0, json["data"]["children_count"]
    assert_equal 0, json["data"]["comments_count"]
    assert_equal 0, json["data"]["assets_count"]
  end

  # ====== CREATE Tests ======

  test "#create adds task with auto-position" do
    sign_in @owner

    assert_difference("BoardTask.count") do
      post :create, params: {
        project_id: @project.id,
        board_task: { title: "New Task", board_column_id: @col1.id, tags: %w[urgent] }
      }
    end

    assert_response :created
    json = response.parsed_body
    assert_equal "New Task", json["data"]["title"]
    assert_equal %w[urgent], json["data"]["tags"]
  end

  test "#create accessible by collaborator" do
    sign_in @collaborator

    assert_difference("BoardTask.count") do
      post :create, params: {
        project_id: @project.id,
        board_task: { title: "Collab Task", board_column_id: @col1.id }
      }
    end

    assert_response :created
  end

  test "#create not accessible by non-member" do
    sign_in @other_user

    assert_no_difference("BoardTask.count") do
      post :create, params: {
        project_id: @project.id,
        board_task: { title: "Hacked", board_column_id: @col1.id }
      }
    end

    assert_response :forbidden
  end

  test "#create with invalid data returns 422" do
    sign_in @owner

    post :create, params: {
      project_id: @project.id,
      board_task: { title: "", board_column_id: @col1.id }
    }

    assert_response :unprocessable_entity
  end

  # ====== UPDATE Tests ======

  test "#update changes task title" do
    sign_in @owner

    patch :update, params: {
      project_id: @project.id,
      id: @task.id,
      board_task: { title: "Updated Title" }
    }

    assert_response :success
    @task.reload
    assert_equal "Updated Title", @task.title
  end

  test "#update accessible by collaborator" do
    sign_in @collaborator

    patch :update, params: {
      project_id: @project.id,
      id: @task.id,
      board_task: { title: "Collab Update" }
    }

    assert_response :success
  end

  # ====== DESTROY Tests ======

  test "#destroy removes task" do
    sign_in @owner

    assert_difference("BoardTask.count", -1) do
      delete :destroy, params: { project_id: @project.id, id: @task.id }
    end

    assert_response :no_content
  end

  # ====== MOVE Tests (Story 21.4) ======

  test "#move moves task to different column" do
    sign_in @owner

    patch :move, params: { project_id: @project.id, id: @task.id, column_id: @col2.id }

    assert_response :success
    @task.reload
    assert_equal @col2.id, @task.board_column_id
  end

  test "#move with explicit position" do
    task2 = BoardTask.create!(title: "T2", board: @board, board_column: @col2)
    sign_in @owner

    patch :move, params: { project_id: @project.id, id: @task.id, column_id: @col2.id, position: 1 }

    assert_response :success
    @task.reload
    assert_equal 1, @task.position
    assert_equal @col2.id, @task.board_column_id
  end

  test "#move within same column (reposition)" do
    task2 = BoardTask.create!(title: "T2", board: @board, board_column: @col1)
    sign_in @owner

    patch :move, params: { project_id: @project.id, id: @task.id, column_id: @col1.id, position: 5 }

    assert_response :success
    @task.reload
    assert_equal 5, @task.position
  end

  test "#move keeps source column positions unchanged" do
    task2 = BoardTask.create!(title: "T2", board: @board, board_column: @col1)
    task3 = BoardTask.create!(title: "T3", board: @board, board_column: @col1)
    sign_in @owner

    patch :move, params: { project_id: @project.id, id: @task.id, column_id: @col2.id }

    assert_response :success
    task2.reload
    task3.reload
    assert_equal 2, task2.position
    assert_equal 3, task3.position
  end

  test "#move to invalid column returns 404" do
    sign_in @owner

    patch :move, params: { project_id: @project.id, id: @task.id, column_id: 999999 }

    assert_response :not_found
  end

  test "#move accessible by collaborator" do
    sign_in @collaborator

    patch :move, params: { project_id: @project.id, id: @task.id, column_id: @col2.id }

    assert_response :success
  end

  test "#move not accessible by non-member" do
    sign_in @other_user

    patch :move, params: { project_id: @project.id, id: @task.id, column_id: @col2.id }

    assert_response :forbidden
  end

  # ====== Assignment Tests (Story 21.3) ======

  test "#update assign task to owner" do
    sign_in @owner

    patch :update, params: {
      project_id: @project.id,
      id: @task.id,
      board_task: { assignee_id: @owner.id }
    }

    assert_response :success
    assert_equal @owner.id, @task.reload.assignee_id
  end

  test "#update assign task to collaborator" do
    sign_in @owner

    patch :update, params: {
      project_id: @project.id,
      id: @task.id,
      board_task: { assignee_id: @collaborator.id }
    }

    assert_response :success
    assert_equal @collaborator.id, @task.reload.assignee_id
  end

  test "#update assign task to non-member returns 422" do
    sign_in @owner

    patch :update, params: {
      project_id: @project.id,
      id: @task.id,
      board_task: { assignee_id: @other_user.id }
    }

    assert_response :unprocessable_entity
  end

  test "#update unassign task" do
    @task.update!(assignee: @owner)
    sign_in @owner

    patch :update, params: {
      project_id: @project.id,
      id: @task.id,
      board_task: { assignee_id: "" }
    }

    assert_response :success
    assert_nil @task.reload.assignee_id
  end

  # ====== N+1 Query Tests ======

  test "#index does not trigger N+1 queries for pending_waits" do
    task2 = BoardTask.create!(title: "Task 2", board: @board, board_column: @col1)
    task3 = BoardTask.create!(title: "Task 3", board: @board, board_column: @col1)

    [ @task, task2, task3 ].each do |task|
      task.task_waits.create!(
        wait_type: :github_checks_completed,
        metadata: { repo_full_name: "org/app", pr_number: 1 },
        creator: @owner
      )
    end

    sign_in @owner

    get :index, params: { project_id: @project.id }

    assert_response :success
  end
end
