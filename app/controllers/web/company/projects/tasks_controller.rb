# frozen_string_literal: true

class Web::Company::Projects::TasksController < Web::Company::Projects::ApplicationController
  include BoardTaskDetail
  include NotFoundPage

  def show
    board = current_project.board
    task = board && find_board_task(board, params[:number])
    return render_not_found unless task

    render inertia: "Projects/Board/TaskPage", props: {
      **board_options_props(board),
      **task_detail_props(task),
      current_user_id: -> { current_user.id }
    }
  end
end
