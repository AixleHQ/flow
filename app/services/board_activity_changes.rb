# frozen_string_literal: true

# The field edits a task_updated activity recorded, named for people: each changed
# field once, with ids turned into the user, team, task or column they point at.
class BoardActivityChanges
  LABELS = {
    "title" => "Title",
    "description" => "Description",
    "task_type" => "Type",
    "priority" => "Priority",
    "assignee_id" => "Assignee",
    "assignee_team_id" => "Assignee",
    "parent_task_id" => "Parent epic",
    "tags" => "Tags",
    "board_column_id" => "Column"
  }.freeze

  ASSIGNEE_FIELDS = %w[assignee_id assignee_team_id].freeze

  def initialize(activity)
    @activity = activity
    recorded = activity.event_type.to_s == "task_updated" ? (activity.metadata || {})["changes"] : nil
    @changes = recorded.is_a?(Hash) ? recorded : {}
  end

  def labels
    fields.map { |field| label(field) }
  end

  def entries
    fields.map do |field|
      before, after = field == "assignee" ? assignee_values : @changes[field]
      { field: field, label: label(field), before: display(field, before), after: display(field, after) }
    end
  end

  private

  # An assignment to a team clears the user and the other way round, so the two
  # columns are one change for a person reading it.
  def fields
    @changes.keys.map { |field| ASSIGNEE_FIELDS.include?(field) ? "assignee" : field }.uniq
  end

  def label(field)
    field == "assignee" ? "Assignee" : LABELS.fetch(field) { field.humanize }
  end

  def assignee_values
    user = @changes.fetch("assignee_id", [])
    team = @changes.fetch("assignee_team_id", [])
    [ user_name(user[0]) || team_name(team[0]), user_name(user[1]) || team_name(team[1]) ]
  end

  def display(field, value)
    return nil if value.blank?

    case field
    when "assignee" then value
    when "task_type", "priority" then value.to_s.humanize
    when "parent_task_id" then task_reference(value)
    when "board_column_id" then @activity.board.board_columns.find_by(id: value)&.name || "Deleted column"
    else value.is_a?(Array) ? value.join(", ") : value.to_s
    end
  end

  def user_name(id)
    return nil if id.blank?

    User.find_by(id: id)&.name || User::DELETED_DISPLAY_NAME
  end

  def team_name(id)
    return nil if id.blank?

    ProjectTeam.find_by(id: id)&.name || "Deleted team"
  end

  def task_reference(id)
    task = @activity.board.board_tasks.find_by(id: id)
    task ? "##{task.number} #{task.title}" : "Deleted task"
  end
end
