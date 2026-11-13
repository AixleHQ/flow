# frozen_string_literal: true

module GitCredentials
  # Marks a checkout the platform made as safe in the container's SYSTEM git config.
  #
  # Since git 2.35.2 a repository whose owner is not the current user is refused
  # ("detected dubious ownership"), root included. The clone is chowned to the
  # adapter's `container_uid` (1001), but several agent images (Kiro CLI, Codex,
  # Gemini CLI, Grok, Antigravity, Copilot, Cursor) run as root, so every git
  # command the agent ran in its own repository failed.
  #
  # `safe.directory` is read only from system, global and command-line config —
  # never from the repository's own — so a `git -C <path> config` does nothing.
  # The system file is used because it applies whichever user the agent runs as
  # and whichever HOME it gets. Only the listed path is trusted; every other path
  # keeps git's protection.
  #
  # Best effort by design: where the exec user cannot write /etc/gitconfig, the
  # agent is a non-root user that owns the checkout and needs no entry, so a
  # failed write must not fail the clone.
  module SafeDirectory
    # Shell for one path, idempotent: an entry already present is not added again
    # (a reconfigure runs on every refresh_github_token call).
    def self.script(path)
      quoted = Shellwords.escape(path.to_s)
      "{ git config --system --get-all safe.directory | grep -qxF -- #{quoted} || " \
        "git config --system --add safe.directory #{quoted}; } || true"
    end
  end
end
