# frozen_string_literal: true

module InternalTools
  # refresh_github_token — re-mint this session's GitHub credential and rewrite
  # the `origin` remote of every clone with it.
  #
  # Repositories are cloned at session start from
  # `https://x-access-token:<token>@github.com/<owner>/<repo>.git` (see
  # SessionContextService#inject_repositories). That token is a GitHub App
  # installation token and GitHub expires it one hour after minting, so a session
  # that outlives the hour fails its first push with a 403 and cannot recover on
  # its own: the dead credential sits in `.git/config` and nothing inside the
  # container can mint a replacement. This tool is the way back.
  class RefreshGithubToken < Base
    CLONE_ROOT = "/workspace/repo"

    tool do
      display_name "Refresh GitHub Token"
      description "Re-mint the GitHub credential for the repositories cloned into this session and " \
                  "rewrite each clone's `origin` remote with it. Use this when git push or fetch fails " \
                  'with a 403, "Invalid username or password" or "could not read Username": the token ' \
                  "baked into the clone URL is a GitHub App installation token that expires one hour " \
                  "after the session starts, so a session that has been running longer than an hour " \
                  "needs this before it can push. Run it, then retry the push — no re-clone and no " \
                  "manual git remote surgery. GitLab clones do not expire and are left alone."
      tags :repositories
      inject_when :github_repositories_attached
      user_attachable false
      idempotent true
      destructive false
      input_schema({
        type: "object",
        required: [],
        properties: {
          repository: {
            type: "string",
            description: "Optional owner/repo (or bare repo name) to refresh. " \
                         "Defaults to every GitHub repository attached to this session."
          }
        }
      })
    end

    def execute
      container_id = session.container_id
      return error("This session has no running container — there is no clone to re-point.") if container_id.blank?

      repos = target_repositories
      return error(nothing_to_refresh_message) if repos.empty?

      refreshed = []
      failed = []
      runtime = ContainerRuntime.build

      repos.each do |repo|
        outcome = refresh(repo, runtime, container_id)
        outcome[:error] ? failed << outcome : refreshed << outcome
      end

      report(refreshed, failed)
    end

    private

    def github_repositories
      session.repositories.includes(:integration).select { |repo| repo.integration&.github? }
    end

    # `repository` accepts either form the agent has at hand: the full_name it
    # sees in the context file, or the bare directory name under /workspace/repo.
    def target_repositories
      repos = github_repositories
      filter = params[:repository].to_s.strip
      return repos if filter.blank?

      repos.select { |repo| repo.full_name.casecmp?(filter) || repo.repo_name.casecmp?(filter) }
    end

    def nothing_to_refresh_message
      if params[:repository].present?
        "No GitHub repository matching #{params[:repository]} is attached to this session. " \
          "Attached GitHub repositories: #{github_repositories.map(&:full_name).presence&.join(', ') || 'none'}."
      else
        "No GitHub repository is attached to this session. Public and GitLab clones carry no " \
          "expiring installation token, so there is nothing to refresh."
      end
    end

    def refresh(repo, runtime, container_id)
      return { repository: repo.full_name, error: "its integration is not active" } unless repo.integration.active?

      token = mint_token(repo)
      path = File.join(CLONE_ROOT, repo.repo_name)
      result = runtime.exec(container_id, set_url_command(repo, path, token))
      exit_code = result[2].to_i

      return { repository: repo.full_name, path: path } if exit_code.zero?

      { repository: repo.full_name,
        error: "git remote set-url exited with #{exit_code}: #{scrub(Array(result[1]).join.strip, token)}" }
    rescue Github::TokenService::ConfigurationError, Github::TokenService::AuthenticationError => e
      { repository: repo.full_name, error: e.message }
    end

    # Scoped to the one repository: unlike the clone-time group token, a
    # repository the installation can no longer reach fails only itself.
    def mint_token(repo)
      Github::TokenService.new(repo.integration).generate_installation_token(repositories: [ repo.repo_name ])
    end

    # `safe.directory` because the clone is owned by the container user while
    # exec runs as root, and git refuses to touch a repository it considers
    # foreign. The chown puts `.git/config` back under the agent's uid — git
    # rewrites it through a lock file + rename, which would otherwise leave it
    # owned by root and unwritable by the agent.
    def set_url_command(repo, path, token)
      safe_path = Shellwords.escape(path)
      url = Shellwords.escape("https://x-access-token:#{token}@github.com/#{repo.full_name}.git")

      [ "sh", "-c",
        "git -c safe.directory=#{safe_path} -C #{safe_path} remote set-url origin #{url} && " \
        "chown #{container_uid}:#{container_uid} #{safe_path}/.git/config" ]
    end

    # Same uid the clone was chowned to. An unknown agent_type raises rather than
    # guessing elsewhere in the app; here the fallback is the shared adapter
    # default, since a wrong owner is better than no refresh at all.
    def container_uid
      @container_uid ||= AgentCredentialsService.for(session.agent_type).adapter.container_uid
    rescue ArgumentError
      1001
    end

    # A token that leaks into an error string ends up in the agent transcript and
    # the tool_results row — the one place the credential must never land.
    def scrub(text, token)
      return text if token.blank?

      text.gsub(token, "[REDACTED]")
    end

    def report(refreshed, failed)
      payload = {
        refreshed: refreshed.map { |r| { repository: r[:repository], path: r[:path] } },
        failed: failed.map { |r| { repository: r[:repository], error: r[:error] } },
        expires_at: 1.hour.from_now.utc.iso8601,
        next_step: "Retry the git push. The credential is good for one hour from now."
      }

      return error(payload.to_json) if refreshed.empty?

      success(payload.to_json)
    end
  end
end
