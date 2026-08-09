# frozen_string_literal: true

module Coder
  # RepoBootstrap — put a usable clone of a project repository on a Coder
  # workspace, and repair one that is already there.
  #
  # This cannot live in the workspace template: cloning a private repository
  # needs a short-lived GitHub App installation token, which the platform mints
  # and the workspace's EC2 instance profile has no way to obtain. So the boxes
  # in the field carry whatever an earlier manual session left behind, and every
  # session pays for it again:
  #
  #   * the clone is `--filter=blob:none` and its promisor remote has no
  #     credentials, so a fetch spawns a second fetch that hangs forever on the
  #     auth helper rather than failing;
  #   * it is shallow and single-branch, so feature branch refs do not exist
  #     locally and each session re-derives `--unshallow` plus a wider refspec.
  #
  # Both are repaired in place here, and a workspace with no clone at all (every
  # box created from a fixed template) gets a full one.
  #
  # The credential never touches the workspace's disk. It travels in the
  # detached launcher's environment (see `SshRunner#exec_detached`) and is read
  # by a `credential.helper` shell function, so it is neither written into
  # `remote.origin.url` nor into the job's command file — both of which outlive
  # the session on a box that is shared and long-lived.
  class RepoBootstrap
    class Error < StandardError; end

    DEFAULT_ROOT = "/root"

    def initialize(integration, ssh_runner: nil)
      @integration = integration
      @ssh_runner  = ssh_runner || Coder::SshRunner.new(integration)
    end

    # Starts detached: a cold clone of a real product repository takes longer
    # than any single MCP call can stay open. Returns the job handle for
    # `coder_job_status`.
    def prepare(workspace_name:, repository:, path: nil)
      target = path.presence || default_path_for(repository)
      raise Error, "path must be absolute" unless target.start_with?("/")

      token = token_for(repository)

      started = @ssh_runner.exec_detached(
        workspace_name: workspace_name,
        command:        script(repository: repository, path: target, authenticated: token.present?),
        env:            token.present? ? { "AIXLE_GH_TOKEN" => token } : {}
      )

      started.merge(
        repository: repository.full_name,
        path:       target,
        branch:     repository.source_branch
      )
    end

    private

    def default_path_for(repository)
      File.join(DEFAULT_ROOT, repository.repo_name.to_s)
    end

    # Scoped to the one repository, like the refresh path: an installation that
    # can no longer reach some other repo does not take this one down with it.
    def token_for(repository)
      return nil if repository.public_source?

      integration = repository.integration
      raise Error, "repository #{repository.full_name} has no active integration" unless integration&.active?

      unless integration.github?
        raise Error, "#{integration.provider} repositories are not supported yet — only GitHub and public clones"
      end

      Github::TokenService.new(integration).generate_installation_token(repositories: [ repository.repo_name ])
    end

    def script(repository:, path:, authenticated:)
      quoted_path   = shell_quote(path)
      quoted_url    = shell_quote(repository.clone_url.to_s)
      quoted_branch = shell_quote(repository.source_branch.to_s)
      auth          = authenticated ? %(-c credential.helper="$HELPER") : ""

      <<~SH
        set -eu
        export GIT_TERMINAL_PROMPT=0
        export GIT_ASKPASS=/bin/true
        HELPER='!f(){ echo username=x-access-token; echo "password=$AIXLE_GH_TOKEN"; };f'
        TARGET=#{quoted_path}
        URL=#{quoted_url}
        BRANCH=#{quoted_branch}

        if [ -d "$TARGET/.git" ]; then
          echo "repairing existing clone at $TARGET"
          git -C "$TARGET" remote set-url origin "$URL"
          # A single-branch clone cannot see the branch under review.
          git -C "$TARGET" config remote.origin.fetch '+refs/heads/*:refs/remotes/origin/*'
          # A promisor remote with no usable credential is what hangs a fetch
          # forever instead of failing it.
          git -C "$TARGET" config --unset-all remote.origin.promisor || true
          git -C "$TARGET" config --unset-all remote.origin.partialclonefilter || true
          # --refetch backfills the blobs the filter skipped; older gits do not
          # have it, and a plain fetch still fixes the refspec half.
          git #{auth} -C "$TARGET" fetch --refetch --prune origin ||
            git #{auth} -C "$TARGET" fetch --prune origin
          if [ -f "$TARGET/.git/shallow" ]; then
            git #{auth} -C "$TARGET" fetch --unshallow || true
          fi
        else
          echo "cloning $URL into $TARGET"
          mkdir -p "$(dirname "$TARGET")"
          git #{auth} clone --branch "$BRANCH" "$URL" "$TARGET"
        fi

        git -C "$TARGET" config --add safe.directory "$TARGET" || true

        echo "--- result ---"
        echo "shallow=$(git -C "$TARGET" rev-parse --is-shallow-repository)"
        echo "remote_branches=$(git -C "$TARGET" for-each-ref --format='%(refname)' refs/remotes/origin | wc -l | tr -d ' ')"
        echo "head=$(git -C "$TARGET" rev-parse --abbrev-ref HEAD)"
      SH
    end

    def shell_quote(value)
      "'#{value.to_s.gsub("'", "'\\\\''")}'"
    end
  end
end
