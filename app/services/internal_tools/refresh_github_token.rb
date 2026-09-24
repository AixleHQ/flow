# frozen_string_literal: true

module InternalTools
  # refresh_github_token — make this session's GitHub checkouts fetch and push
  # with fresh credentials.
  #
  # Repositories clone with a clean remote and the platform's git credential
  # helper (GitCredentials::SessionGitSetup), which asks for a new, repository-
  # scoped token on every fetch and push — so the hour an installation token
  # lasts no longer ends a session's ability to push. This tool re-applies that
  # configuration to a checkout that does not have it (a clone made before it
  # existed carries an expiring token in its remote); on any other it is a no-op.
  class RefreshGithubToken < Base
    tool do
      display_name "Refresh GitHub Token"
      description "Repair the git credentials of the GitHub repositories cloned into this session. " \
                  "Credentials normally refresh on their own on every fetch and push; use this only " \
                  'when git push or fetch fails with a 403, "Invalid username or password" or ' \
                  '"could not read Username". Run it, then retry — no re-clone and no manual git ' \
                  "remote surgery."
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
            description: "Optional owner/repo (or bare repo name) to repair. " \
                         "Defaults to every GitHub repository attached to this session."
          }
        }
      })
    end

    def execute
      container_id = session.container_id
      return error("This session has no running container — there is no clone to repair.") if container_id.blank?

      repos = target_repositories
      return error(nothing_to_refresh_message) if repos.empty?

      runtime = ContainerRuntime.build
      setup = GitCredentials::SessionGitSetup.new(runtime: runtime, container_id: container_id, session: session)
      setup.install_helper!(container_uid)

      refreshed = []
      failed = []
      repos.each do |repo|
        outcome = refresh(repo, runtime, container_id, setup)
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

    def refresh(repo, runtime, container_id, setup)
      return { repository: repo.full_name, error: "its integration is not active" } unless repo.integration.active?

      path = RepositoryWorkspacePath.for_repository(session, repo)
      result = runtime.exec(container_id, [ "sh", "-c", setup.reconfigure_script(repo, path, container_uid) ])
      exit_code = result[2].to_i
      return { repository: repo.full_name, path: path } if exit_code.zero?

      { repository: repo.full_name, error: "git config exited with #{exit_code}: #{Array(result[1]).join.strip.truncate(300)}" }
    end

    # Same uid the clone was chowned to. An unknown agent_type raises rather than
    # guessing elsewhere in the app; here the fallback is the shared adapter
    # default, since a wrong owner is better than no repair at all.
    def container_uid
      @container_uid ||= AgentCredentialsService.for(session.agent_type).adapter.container_uid
    rescue ArgumentError
      1001
    end

    def report(refreshed, failed)
      payload = {
        refreshed: refreshed.map { |r| { repository: r[:repository], path: r[:path] } },
        failed: failed.map { |r| { repository: r[:repository], error: r[:error] } },
        next_step: "Retry the git push. Credentials are fetched fresh on every git operation."
      }

      return error(payload.to_json) if refreshed.empty?

      success(payload.to_json)
    end
  end
end
