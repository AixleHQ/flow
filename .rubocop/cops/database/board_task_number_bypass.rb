# frozen_string_literal: true

module RuboCop
  module Cop
    module Database
      # Bans writing board tasks past the per-board number counter.
      #
      # A task's `number` comes from `Board#next_task_number!`, which bumps
      # `boards.last_task_number` under a row lock. `insert_all`, `upsert_all`,
      # `update_all(number: ...)` and hand-written `INSERT INTO board_tasks` skip
      # it. Without a number the insert fails on NOT NULL; with one, the counter
      # falls behind and the next ordinary create on that board hits the
      # (board_id, number) unique index — failing in someone else's request, and
      # on every retry, until the counter is repaired by hand.
      #
      # Create tasks through TaskService / BoardTask.create. A genuine bulk path
      # needs a `Board#reserve_task_numbers!(count)` that bumps the counter by
      # `count` in one UPDATE ... RETURNING, and numbers from that range.
      class BoardTaskNumberBypass < Base
        MSG = "Board task numbers come from Board#next_task_number!; bulk and raw writes skip it " \
              "and leave the board counter behind. Create tasks through TaskService / BoardTask.create."

        BULK_WRITES = %i[insert insert! insert_all insert_all! upsert upsert_all].freeze
        RAW_INSERT = /\bINSERT\s+INTO\s+"?board_tasks"?\b/i

        def_node_matcher :board_task_root?, <<~PATTERN
          {(const {nil? cbase} :BoardTask) (send _ :board_tasks) (csend _ :board_tasks)}
        PATTERN

        def on_send(node)
          writes = BULK_WRITES.include?(node.method_name) ||
                   (node.method_name == :update_all && sets_number?(node.arguments))
          add_offense(node) if writes && board_task_chain?(node.receiver)
        end
        alias on_csend on_send

        def on_str(node)
          return if node.parent&.dstr_type?

          add_offense(node) if node.value.match?(RAW_INSERT)
        end

        def on_dstr(node)
          text = node.each_child_node(:str).map(&:value).join
          add_offense(node) if text.match?(RAW_INSERT)
        end

        private

        # `BoardTask.where(...)`, `board.board_tasks.active` and the like: any
        # relation built from the model or the association.
        def board_task_chain?(receiver)
          while receiver
            return true if board_task_root?(receiver)
            return false unless receiver.call_type?

            receiver = receiver.receiver
          end
          false
        end

        def sets_number?(args)
          args.any? do |arg|
            arg.hash_type? && arg.pairs.any? { |pair| %i[sym str].include?(pair.key.type) && pair.key.value.to_s == "number" }
          end
        end
      end
    end
  end
end
