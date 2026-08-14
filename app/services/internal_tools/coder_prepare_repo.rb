# frozen_string_literal: true

module InternalTools
  # coder_prepare_repo — put a working clone of a session repository on an
  # allocated Coder workspace, or repair the one already there.
  #
  # Runs detached (a cold clone outlives any single MCP call) and returns a
  # `job_id` to poll with `coder_job_status`.
  class CoderPrepareRepo < Base
    tool do
      display_name "Coder: Prepare Repository"
      description "Clone a session repository onto an allocated Coder workspace, or repair an existing clone " \
                  "(re-point origin, widen the refspec so feature branches exist locally, drop a partial-clone " \
                  "filter whose fetches hang, unshallow). Run this once after coder_allocate_machine, before " \
                  "any git work on the box. Pass `ref` to also check out the exact branch, tag or commit under " \
                  "test. Returns a `job_id` — poll coder_job_status until it reports exited with exit_code 0; its " \
                  "`result` carries the checked-out `head_sha` and the working-tree state. The GitHub credential " \
                  "is short-lived and never written to the workspace disk."
      tags :coder
      inject_when :coder_integration_connected
      requires_integration :coder
      input_schema({
        type: "object",
        required: %w[workspace_name],
        properties: {
          workspace_name: {
            type: "string",
            description: "Workspace name returned by coder_allocate_machine."
          },
          repository: {
            type: "string",
            description: "owner/repo (or bare repo name) to prepare. Defaults to the session's only repository."
          },
          path: {
            type: "string",
            description: "Absolute path for the clone. Defaults to /root/<repo name>; pass the existing path " \
                         "(e.g. /root/app) to adopt a clone a previous session left behind."
          },
          ref: {
            type: "string",
            description: "Branch, tag or commit to fetch and check out once the clone is ready — e.g. a PR head " \
                         "sha, so a test run cannot report green for the wrong revision. Resolved in that order " \
                         "(branch, tag, commit) and checked out with --force, discarding local edits. Omit to " \
                         "leave the clone on the repository's default branch. A ref that exists nowhere on " \
                         "origin fails the job with exit_code #{Coder::RepoBootstrap::REF_NOT_FOUND_EXIT_CODE}."
          }
        }
      })
    end

    include Concerns::CoderResolver

    def execute
      require_coder!

      workspace_name = params[:workspace_name].to_s
      return error("workspace_name is required") if workspace_name.empty?

      lock_service = Coder::LockService.new(coder_integration)
      unless lock_service.held_by_session?(workspace_name: workspace_name, terminal_session_id: session.id)
        return error("session does not hold the lock for workspace #{workspace_name}")
      end

      lock_service.touch(workspace_name: workspace_name, terminal_session_id: session.id)

      repository = resolve_repository
      return error(no_repository_message) if repository.nil?

      started = Coder::RepoBootstrap.new(coder_integration).prepare(
        workspace_name: workspace_name,
        repository:     repository,
        path:           params[:path].presence,
        ref:            params[:ref].presence
      )

      success(started.merge(next_step: next_step_for(started)).to_json)
    rescue Concerns::CoderResolver::NotConfiguredError => e
      error(e.message)
    rescue Coder::RepoBootstrap::Error,
           Coder::SshRunner::CommandError,
           Github::TokenService::ConfigurationError,
           Github::TokenService::AuthenticationError => e
      error("coder_prepare_repo: #{e.message}")
    end

    private

    # The clone runs detached, so the checked-out revision is only knowable once
    # the job has finished — point the caller at the poll that carries it.
    def next_step_for(started)
      base = "poll coder_job_status with this job_id until state=exited; exit_code 0 means the clone is ready"
      return base if started[:ref].blank?

      "#{base}. Its `result` reports head_sha (the commit #{started[:ref]} resolved to), ref_type and worktree; " \
        "exit_code #{Coder::RepoBootstrap::REF_NOT_FOUND_EXIT_CODE} means the ref does not exist on origin"
    end

    def repositories
      @repositories ||= session.repositories.includes(:integration).to_a
    end

    # Accepts either form the agent has at hand: the full_name from the context
    # file, or the bare repository name.
    def resolve_repository
      filter = params[:repository].to_s.strip
      return repositories.first if filter.blank? && repositories.one?
      return nil if filter.blank?

      repositories.find { |repo| repo.full_name.to_s.casecmp?(filter) || repo.repo_name.to_s.casecmp?(filter) }
    end

    def no_repository_message
      names = repositories.map(&:full_name)
      return "No repository is attached to this session." if names.empty?

      if params[:repository].present?
        "No repository matching #{params[:repository]} is attached to this session. Attached: #{names.join(', ')}."
      else
        "This session has #{names.size} repositories (#{names.join(', ')}) — pass `repository` to pick one."
      end
    end
  end
end
