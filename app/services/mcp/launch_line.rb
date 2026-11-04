# frozen_string_literal: true

module MCP
  # A stdio server's launch line and the rules it must meet to start. MCPServer
  # applies them when a row is written; Templates::Validator applies them to a
  # template's line where there is no database — the catalog repository's CI runs
  # the validator in a container without one, and even building an unsaved
  # MCPServer reads its columns from the database. So the rules live here, on a
  # plain object.
  #
  # The process is spawned directly, not through a shell, so the shapes refused
  # below are accepted by a form and then fail invisibly at session start — the
  # process never comes up, and a server that never starts looks exactly like one
  # nobody called.
  class LaunchLine
    # `FOO=bar cmd` is shell syntax for a one-off environment variable. Spawned
    # directly it is read as the name of the program to run.
    ENV_ASSIGNMENT_FORMAT = /\A[A-Za-z_][A-Za-z0-9_]*=/
    # Matched as whole tokens, so a quoted argument that merely contains one
    # (`--filter="a && b"`) is left alone.
    SHELL_OPERATORS = %w[| || & && ; > >> < << 2>&1].freeze

    # A package runner installs the newest release at every session start unless the
    # spec names one, so a publisher (or whoever takes over the package) changes what
    # runs inside every agent container with the next release. `latest`, a range and a
    # bare name are not pins.
    PACKAGE_RUNNERS = %w[npx uvx pipx].freeze
    EXACT_VERSION = /\A\d+(\.\d+){0,3}([-+][0-9A-Za-z.-]+)?\z/

    attr_reader :command, :args

    # A line given whole (`npx pkg@1.0.0 --flag`) is split into the executable and
    # its argv, as MCPServer stores it; a single token keeps the argv given with it.
    def initialize(command, args = [])
      @command = command.to_s
      @args = Array(args).map(&:to_s)
      tokens = Shellwords.split(@command)
      @command, *@args = tokens if tokens.size > 1
    rescue ArgumentError
      @unbalanced_quote = true
    end

    # Messages for the server's `command`; empty when the line can be launched.
    def errors
      return [ "has an unbalanced quote" ] if @unbalanced_quote

      [ env_assignment, shell_operator, unavailable_runtime, unpinned_package ].compact
    end

    private

    def env_assignment
      return unless command.match?(ENV_ASSIGNMENT_FORMAT)

      "must start with the program to run — put environment variables in the Env section"
    end

    def shell_operator
      return if ([ command ] + args).none? { |token| SHELL_OPERATORS.include?(token) }

      "cannot use shell operators — the process is launched directly, without a shell"
    end

    # Same policy the connector catalog applies to a package target, from the same
    # list: a runtime the agent image does not carry cannot be launched by hand
    # either.
    def unavailable_runtime = MCP::ConnectorManifest::UNAVAILABLE_RUNTIMES[command]

    def unpinned_package
      return unless PACKAGE_RUNNERS.include?(command)

      spec = package_spec
      return if spec.nil? || pinned?(spec)

      "must pin #{spec.presence || 'the package'} to an exact version " \
        "(#{command == 'npx' ? 'name@1.2.3' : 'name==1.2.3'}) — unpinned, every session installs whatever was released last"
    end

    # The registry package the runner will fetch, or nil when the line names something
    # else — a local path or a URL, which is not a registry release. "" when there is
    # no package at all.
    def package_spec
      argv = command == "pipx" ? args.drop_while { |token| token != "run" }.drop(1) : args
      explicit = argv.each_with_index.find { |token, _| %w[-p --package --from --spec].include?(token) }
      spec = explicit ? argv[explicit.last + 1] : argv.find { |token| !token.start_with?("-") }
      spec ||= argv.find { |token| token.start_with?("--package=", "--from=", "--spec=") }&.split("=", 2)&.last
      return "" if spec.nil?
      return nil if spec.start_with?(".", "/", "~") || spec.include?("://") || spec.include?(":")

      spec
    end

    def pinned?(spec)
      # Every adapter rewrites this one to the version baked into the agent image
      # (BaseAdapter#mcp_stdio_args), whatever the line says.
      return true if command == "npx" && spec.split(/(?<=.)@/, 2).first == Agents::BaseAdapter::PLAYWRIGHT_MCP_PACKAGE

      version = if command == "npx"
        name_end = spec.start_with?("@") ? spec.index("@", 1) : spec.index("@")
        name_end && spec[(name_end + 1)..]
      else
        spec.split(/==|@/, 2)[1]
      end
      version.to_s.match?(EXACT_VERSION)
    end
  end
end
