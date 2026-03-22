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

  def initialize(company)
    @company = company
  end

  def call
    rows = BoardColumn
      .joins(board: :project)
      .where(projects: { company_id: company.id })
      .select("board_columns.name, COUNT(board_tasks.id) AS task_count")
      .joins("LEFT OUTER JOIN board_tasks ON board_tasks.board_column_id = board_columns.id")
      .group("board_columns.id, board_columns.name, board_columns.position")
      .order("board_columns.position ASC")

    columns = rows.map { |row| ColumnCount.new(name: row.name, count: row.task_count.to_i) }
    total = columns.sum(&:count)

    Result.new(columns: columns, total: total)
  end

  private

  attr_reader :company
end
