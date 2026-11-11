# frozen_string_literal: true

module ContainerRuntime
  # The addresses an agent container calls back to the platform on
  # (docs/design/agent-runtimes/DESIGN.md §6.6), by name. A session reads
  # them through its runtime, `ContainerRuntime.callback_url(:mcp, session)`
  # or `runtime.callback_url(:mcp, session)` when it already holds one, and
  # never from Settings itself: every runtime but RunnerRuntime answers the
  # Settings value below unchanged, and RunnerRuntime answers the session's
  # local callback proxy (Runners::Proxy). The names:
  #
  # - `:mcp`: the session's MCP server (`Settings.mcp.server_url`);
  # - `:agent_credential_sync`, `:agent_credential_refresh`: the agent
  #   credential write-back and the refresh broker;
  # - `:git_credentials`: git credentials for GitHub, GitLab and Bitbucket;
  # - `:azure_git_credentials`: git credentials for Azure DevOps;
  # - `:cloud_credentials`: cloud credential vending (Amazon Bedrock);
  # - `:container_assets`: the host stored files are downloaded from, for
  #   ContainerAssetUrl;
  # - `:otel`: the OTLP endpoint, which is not Rails but `otlp-ingest`. Nil
  #   means the session gets no telemetry endpoint.
  module CallbackUrls
    HOSTED = {
      mcp: -> { Settings.mcp.server_url },
      agent_credential_sync: -> { Settings.agents.credential_sync_url },
      agent_credential_refresh: -> { Settings.agents.credential_refresh_url },
      git_credentials: -> { Settings.git.credentials_url },
      azure_git_credentials: -> { Settings.azure_devops.git_credentials_url },
      cloud_credentials: -> { Settings.cloud.credentials_url },
      container_assets: -> { Settings.container_asset_host },
      otel: -> { Settings.otel.endpoint }
    }.freeze

    NAMES = HOSTED.keys.freeze

    module_function

    # The hosted address of a callback: the Settings value, unchanged.
    def hosted(name)
      HOSTED.fetch(name.to_sym) { raise ArgumentError, "unknown callback #{name.inspect}" }.call
    end
  end
end
