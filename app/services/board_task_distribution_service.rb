# frozen_string_literal: true

class BoardTaskDistributionService
  ColumnCount = Struct.new(:name, :count, keyword_init: true)

  Result = Struct.new(:columns, :total, keyword_init: true) do
    def to_h
      {
        columns: columns.map { |c| { name: c.name, count: c.count } },
        total: total
      }
    end
  end

  def initialize(company, project: nil, include_archived: false)
    @company = company
    @project = project
    @include_archived = include_archived
  end

  def call
    rows = BoardColumn
      .joins(board: :project)
      .then { |q| project ? q.where(boards: { project_id: project.id }) : q.where(projects: { company_id: company.id }) }
      .select("board_columns.name, COUNT(board_tasks.id) AS task_count")
      .joins(board_tasks_join)
      .group("board_columns.id, board_columns.name, board_columns.position")
      .order("board_columns.position ASC")

    columns = rows.map { |row| ColumnCount.new(name: row.name, count: row.task_count.to_i) }
    total = columns.sum(&:count)

    Result.new(columns: columns, total: total)
  end

  private

  attr_reader :company, :project, :include_archived

  def board_tasks_join
    board_tasks = BoardTask.arel_table
    board_columns = BoardColumn.arel_table

    condition = board_tasks[:board_column_id].eq(board_columns[:id])
    condition = condition.and(board_tasks[:archived_at].eq(nil)) unless include_archived

    board_columns.join(board_tasks, Arel::Nodes::OuterJoin).on(condition).join_sources
  end
end
