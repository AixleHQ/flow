# frozen_string_literal: true

module Seeds
  module Semgrep
    def self.seed!(company)
      tool = company.tools.find_or_initialize_by(name: "semgrep")
      tool.update!(
        display_name: "Semgrep Scan",
        description: "Run Semgrep static analysis on a Git repository. " \
                     "Clones the repo inside the container, runs semgrep scan with auto-config, " \
                     "and outputs JSON results to stdout. " \
                     "Requires repository_id — the repo must be attached to your session. " \
                     "GitHub token is resolved automatically from the integration.",
        docker_image: "semgrep/semgrep:latest",
        command: <<~'SH'.squish,
          git clone --depth=1 --branch ${BRANCH:-main}
            https://x-access-token:${GITHUB_TOKEN}@github.com/${REPO}.git /src
          && cd /src
          && semgrep scan --config=${SEMGREP_RULES:-auto} --json --quiet
        SH
        kind: :custom,
        required_config_items: %w[],
        input_schema: {
          type: "object",
          properties: {
            repository_id: { type: "integer", description: "ID of a repository attached to your session" },
            BRANCH: { type: "string", description: "Branch to scan (default: main)", default: "main" },
            SEMGREP_RULES: { type: "string", description: "Semgrep ruleset (default: auto)", default: "auto" }
          },
          required: %w[repository_id]
        }
      )

      puts "  Tool seeded: #{tool.display_name} (company: #{company.name})"
    end
  end
end
