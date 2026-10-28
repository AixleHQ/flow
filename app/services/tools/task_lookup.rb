# frozen_string_literal: true

module Tools
  # People name a board task by the #N the board shows — also the `n` in a
  # board link — while a task's `id` appears nowhere in the UI. Every tool that
  # takes a task accepts either, so an agent never has to ask a person for an id
  # they have no way to find.
  module TaskLookup
    TASK_ID_PARAM = "Internal task id (the `id` field). Not the #N shown on the board — that goes in task_number."
    TASK_NUMBER_PARAM = "The task's number on the board: what a person means by \"#12\", and the `n` in a " \
                        "board link (`?n=12`). Give this or task_id."

    private

    # Nil when no task matches, and when the call names none or both;
    # #task_not_found says which. `default_id` stands in when the call names none.
    def find_task(scope, default_id: nil)
      id = params[:task_id].presence
      number = params[:task_number].presence
      return if scope.nil? || (id && number)
      return scope.find_by(number: number) if number

      id ||= default_id
      scope.find_by(id: id) if id
    end

    def task_not_found
      id = params[:task_id].presence
      number = params[:task_number].presence
      if id && number then "Pass task_number or task_id, not both"
      elsif number then "Task ##{number} not found on this board"
      elsif id then "Task not found on this board: no task has id #{id}. The #N people see on the board goes in task_number"
      else "Pass task_number (the #N on the board) or task_id"
      end
    end
  end
end
