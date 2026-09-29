# frozen_string_literal: true

module Gitlab
  # The GitLab instance this deployment talks to. GITLAB_ENDPOINT names its API
  # (https://gitlab.example.com/api/v4); clones go to the same host. Hardcoding
  # gitlab.com for clones sent a self-managed instance's token to gitlab.com.
  module Host
    module_function

    def api_endpoint
      Settings.gitlab.endpoint.presence || "https://gitlab.com/api/v4"
    end

    def web_base
      api_endpoint.sub(%r{/api/v\d+/?\z}, "")
    end
  end
end
