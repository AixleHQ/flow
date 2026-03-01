# frozen_string_literal: true

class BoardChannel < ApplicationCable::Channel
  def subscribed
    @board = Board.find_by(id: params[:board_id])
    return reject unless @board && can_access?(@board)

    stream_for @board
  end

  def refresh
    return unless @board

    @board.reload
    transmit({
      "type" => "board_refresh",
      "data" => BoardSerializer.new(@board, include_associations: true).as_json
    })
  end

  class << self
    def broadcast_event(board, event_type, data, actor_id: nil)
      broadcast_to(board, {
        "type" => event_type,
        "data" => data,
        "actor_id" => actor_id
      })
    end
  end

  private

  def can_access?(board)
    return false unless current_user

    board.project.accessible_by?(current_user)
  end
end
