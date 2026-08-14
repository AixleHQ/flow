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

    # Exit code the job uses when the requested `ref` is neither a branch, a tag
    # nor a commit on origin. Distinct from 1 so an agent can tell "you asked for
    # a revision that does not exist" apart from a clone that broke.
    REF_NOT_FOUND_EXIT_CODE = 3

    # The ref travels to the workspace inside a quoted shell word, so this is not
    # a quoting guard — it is what turns a typo (or an option-looking string) into
    # an immediate, readable error instead of a job that fails minutes later.
    # Deliberately narrower than `git check-ref-format`: it covers branch, tag and
    # commit spellings a caller actually passes, and nothing that needs escaping.
    REF_FORMAT = %r{\A[A-Za-z0-9][A-Za-z0-9._/+-]{0,254}\z}

    def initialize(integration, ssh_runner: nil)
      @integration = integration
      @ssh_runner  = ssh_runner || Coder::SshRunner.new(integration)
    end

    # Starts detached: a cold clone of a real product repository takes longer
    # than any single MCP call can stay open. Returns the job handle for
    # `coder_job_status`.
    #
    # `ref` is optional. With it, the job also checks out that branch, tag or
    # commit, so a caller can prepare the exact revision under test in one
    # operation instead of hand-rolling fetch/checkout over SSH. Without it the
    # clone is left on the repository's source branch, as before.
    def prepare(workspace_name:, repository:, path: nil, ref: nil)
      target = path.presence || default_path_for(repository)
      raise Error, "path must be absolute" unless target.start_with?("/")

      ref = ref.to_s.strip.presence
      validate_ref!(ref) if ref

      token = token_for(repository)

      started = @ssh_runner.exec_detached(
        workspace_name: workspace_name,
        command:        script(repository: repository, path: target, authenticated: token.present?, ref: ref),
        env:            token.present? ? { "AIXLE_GH_TOKEN" => token } : {}
      )

      handle = started.merge(
        repository: repository.full_name,
        path:       target,
        branch:     repository.source_branch
      )
      ref ? handle.merge(ref: ref) : handle
    end

    private

    def validate_ref!(ref)
      return if REF_FORMAT.match?(ref) &&
                !ref.include?("..") &&
                !ref.include?("//") &&
                !ref.end_with?(".lock", "/", ".")

      raise Error, "ref #{ref.inspect} is not a valid branch, tag or commit name"
    end

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

    def script(repository:, path:, authenticated:, ref: nil)
      quoted_path   = shell_quote(path)
      quoted_url    = shell_quote(repository.clone_url.to_s)
      quoted_branch = shell_quote(repository.source_branch.to_s)
      quoted_ref    = shell_quote(ref.to_s)
      auth          = authenticated ? %(-c credential.helper="$HELPER") : ""

      <<~SH
        set -eu
        export GIT_TERMINAL_PROMPT=0
        export GIT_ASKPASS=/bin/true
        HELPER='!f(){ echo username=x-access-token; echo "password=$AIXLE_GH_TOKEN"; };f'
        TARGET=#{quoted_path}
        URL=#{quoted_url}
        BRANCH=#{quoted_branch}
        REF=#{quoted_ref}
        REF_TYPE=""

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

        #{checkout_section(ref: ref, auth: auth)}
        if [ -n "$(git -C "$TARGET" status --porcelain)" ]; then WORKTREE=dirty; else WORKTREE=clean; fi

        echo "#{Coder::SshRunner::JOB_RESULT_MARKER}"
        echo "shallow=$(git -C "$TARGET" rev-parse --is-shallow-repository)"
        echo "remote_branches=$(git -C "$TARGET" for-each-ref --format='%(refname)' refs/remotes/origin | wc -l | tr -d ' ')"
        echo "head=$(git -C "$TARGET" rev-parse --abbrev-ref HEAD)"
        echo "head_sha=$(git -C "$TARGET" rev-parse HEAD)"
        echo "requested_ref=$REF"
        echo "ref_type=$REF_TYPE"
        echo "worktree=$WORKTREE"
      SH
    end

    # Resolution order is fixed — branch, then tag, then commit — so one ref always
    # lands on one revision, whatever else the box carries. The probing fetches are
    # expected to fail for the kinds the ref is not, so their stderr is dropped; a
    # credential problem has already failed the clone/repair above under `set -e`.
    #
    # Emitted only when a ref was asked for: a caller that omits it gets the script
    # it got before, with no checkout in it at all.
    def checkout_section(ref:, auth:)
      return "" if ref.blank?

      <<~SH
        echo "checking out $REF"
        if git #{auth} -C "$TARGET" fetch --force origin "+refs/heads/$REF:refs/remotes/origin/$REF" 2>/dev/null; then
          REF_TYPE=branch
          git -C "$TARGET" checkout --force -B "$REF" "refs/remotes/origin/$REF"
        elif git #{auth} -C "$TARGET" fetch --force origin "+refs/tags/$REF:refs/tags/$REF" 2>/dev/null; then
          REF_TYPE=tag
          git -C "$TARGET" checkout --force --detach "refs/tags/$REF"
        else
          # A bare commit is not fetchable by name on every server (it needs
          # uploadpack.allowReachableSHA1InWant), so this may be a no-op and the
          # widened refspec above is what brought the object in.
          git #{auth} -C "$TARGET" fetch --force origin "$REF" 2>/dev/null || true
          if git -C "$TARGET" rev-parse --verify --quiet "$REF^{commit}" >/dev/null; then
            REF_TYPE=commit
            git -C "$TARGET" checkout --force --detach "$REF"
          else
            echo "ref $REF is not a branch, tag or commit on origin" >&2
            exit #{REF_NOT_FOUND_EXIT_CODE}
          fi
        fi
      SH
    end

    def shell_quote(value)
      "'#{value.to_s.gsub("'", "'\\\\''")}'"
    end
  end
end
