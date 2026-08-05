# frozen_string_literal: true

require "test_helper"
require "open3"
require "tmpdir"

# db/schema.rb must be reproducible from db/migrate alone.
#
# Every database we develop and test against is built with `db:schema:load`, so a
# column that lives ONLY in schema.rb — hand-added to somebody's development
# database and then captured by a schema dump — is present and healthy in
# development, in test and in CI. Production is the one database built by running
# migrations, so it is the one place the column is missing, and nothing before
# deploy can notice.
#
# That is how `mcp_servers.args` reached production without a migration and took
# the connector install down with it:
#
#   ActiveModel::UnknownAttributeError: unknown attribute 'args' for MCPServer
#   Web::Company::Projects::ConnectorsController#create
#
# This test replays the migrations into a throwaway database and diffs the dump
# against the committed schema, which catches the whole class of drift rather
# than the one column that happened to blow up first.
class SchemaParityTest < ActiveSupport::TestCase
  PARITY_DATABASE = "aixle_schema_parity"

  # Replaying ~200 migrations in a subprocess is slow by nature; it is worth one
  # slot in the suite because nothing cheaper can see production's schema.
  test "db/schema.rb is reproducible from db/migrate" do
    Dir.mktmpdir("schema-parity") do |dir|
      seed = File.join(dir, "empty_schema.rb")
      dumped = File.join(dir, "dumped_schema.rb")
      # `db:migrate` loads the schema file into an empty database before it
      # migrates. Point it at an empty one so the migrations, and only the
      # migrations, build the result.
      File.write(seed, "ActiveRecord::Schema[8.1].define(version: 0) do\nend\n")

      begin
        assert_targets_parity_database
        run_rails!(%w[db:drop db:create db:migrate], schema: seed)
        run_rails!(%w[db:schema:dump], schema: dumped)

        assert_no_drift(committed_schema, File.read(dumped))
      ensure
        run_rails(%w[db:drop], schema: seed)
      end
    end
  end

  private

  def committed_schema
    Rails.root.join("db/schema.rb").read
  end

  def assert_no_drift(committed, replayed)
    only_committed = committed.lines.map(&:rstrip) - replayed.lines.map(&:rstrip)
    only_replayed = replayed.lines.map(&:rstrip) - committed.lines.map(&:rstrip)
    return if only_committed.empty? && only_replayed.empty?

    flunk <<~MESSAGE
      db/schema.rb does not match a database built from db/migrate.

      In schema.rb but NOT produced by any migration (missing in production):
      #{only_committed.map { |line| "  #{line.strip}" }.join("\n").presence || '  (none)'}

      Produced by the migrations but NOT in schema.rb (schema.rb is stale):
      #{only_replayed.map { |line| "  #{line.strip}" }.join("\n").presence || '  (none)'}

      Add the missing migration (or re-dump schema.rb from the test database).
    MESSAGE
  end

  # Cheap insurance before `db:drop`: prove the subprocess really is pointed at
  # the throwaway database and not at the suite's own.
  def assert_targets_parity_database
    output = run_rails!(%w[runner], schema: nil, args: [ "print ActiveRecord::Base.connection_db_config.database" ])

    assert_includes output, PARITY_DATABASE,
      "refusing to run: the parity subprocess is not pointed at #{PARITY_DATABASE}"
  end

  def run_rails!(tasks, schema:, args: [])
    output, status = run_rails(tasks, schema: schema, args: args)
    assert status.success?, "`bin/rails #{tasks.join(' ')}` failed:\n#{output}"
    output
  end

  def run_rails(tasks, schema:, args: [])
    env = {
      "RAILS_ENV" => "test",
      "DATABASE_URL" => parity_database_url,
      "SKIP_COVERAGE" => "1",
      "VERBOSE" => "false"
    }
    env["SCHEMA"] = schema if schema

    Open3.capture2e(env, Rails.root.join("bin/rails").to_s, *tasks, *args, chdir: Rails.root.to_s)
  end

  def parity_database_url
    config = ActiveRecord::Base.connection_db_config.configuration_hash
    userinfo = [ config[:username], config[:password] ].compact.join(":")

    "postgres://#{userinfo}@#{config[:host]}:#{config[:port]}/#{PARITY_DATABASE}"
  end
end
