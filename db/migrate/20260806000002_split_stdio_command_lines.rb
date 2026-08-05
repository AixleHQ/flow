# frozen_string_literal: true

require "shellwords"

# Bring hand-written stdio servers onto the storage shape a catalog install already
# uses: the executable in `command`, its argv in `args`. Until now the install form
# stored the whole line in `command`, so the same column meant different things
# depending on which path wrote the row — which is how the resolver came to read
# only one of them (see MCPServer#launch_args).
#
# Conservative by construction: a row is only rewritten when its line parses
# cleanly and actually carries arguments. Anything else — an unbalanced quote, a
# single-token command, a row a catalog install already split — is left exactly as
# it is, and keeps working through the #launch_args fallback.
#
# Idempotent: after the split each `command` is a single token, so a re-run matches
# nothing.
class SplitStdioCommandLines < ActiveRecord::Migration[8.1]
  class MigMCPServer < ActiveRecord::Base
    self.table_name = "mcp_servers"
  end

  def up
    MigMCPServer.where(transport: "stdio").find_each do |server|
      next if server.args.present?

      tokens = begin
        Shellwords.split(server.command.to_s)
      rescue ArgumentError
        []
      end
      next if tokens.size < 2

      server.update_columns(command: tokens.first, args: tokens.drop(1))
    end
  end

  # Hand-written rows only. A catalog install was always stored split, so rejoining
  # it would not be a rollback — it would be damage `up` never did.
  #
  # Rejoining is lossy in the same way any re-quoting is, but the column it writes
  # back is the one the old code read, so a rollback lands on a working row.
  def down
    MigMCPServer.where(transport: "stdio", connector_name: nil).find_each do |server|
      next if server.args.blank?

      line = ([ server.command.to_s ] + Array(server.args).map(&:to_s)).map do |token|
        token.match?(/[\s"']/) ? %("#{token.gsub('"', '\"')}") : token
      end.join(" ")

      server.update_columns(command: line, args: [])
    end
  end
end
