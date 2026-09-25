# frozen_string_literal: true

# One refresh broadcast per board per unit of work. Every task, column and
# binding change touched its board, and so did every recorded activity: a task
# move broadcast a board-wide refresh twice, a bulk action once per task, and
# every viewer reloaded each time. Inside a request, job or other executor run
# the touches are collected and each board is touched once at the end; outside
# one (a console, a direct test) it is touched at once.
module BoardRefresh
  module_function

  def request(board)
    return unless board&.persisted?
    return board.touch unless Rails.application.executor.active?

    pending[board.id] ||= board
  end

  def flush!
    boards = pending.values
    pending.clear
    boards.each do |board|
      board.touch
    rescue ActiveRecord::ActiveRecordError => e
      Rails.logger.warn("[BoardRefresh] board #{board.id} not refreshed: #{e.class}: #{e.message}")
    end
  end

  def pending
    ActiveSupport::IsolatedExecutionState[:board_refresh_pending] ||= {}
  end
end
