# frozen_string_literal: true

module AzureDevops
  # Everything the container needs in order to clone, fetch and push Azure
  # repositories, and the one clone command that does it.
  #
  # Two Git mechanisms are in play and they are not interchangeable:
  #
  # - The CLONE carries its credential as an `http.extraheader` supplied through
  #   `--config-env`, which is what Microsoft documents. The value comes from
  #   the process environment, never from argv, so it does not appear in `ps`,
  #   shell history or the session log.
  # - EVERY LATER `git fetch`/`git push` the agent runs on its own goes through
  #   the credential helper, because nothing can inject a per-command header
  #   into a command the agent types. The helper asks the platform each time,
  #   which is also what makes an hour-long Entra token survive a long session.
  #
  # Modern Git (2.46+) can carry a bearer credential through the helper protocol
  # itself (`authtype`/`credential`/`ephemeral`). That is better and is
  # unverified against Azure Repos, so it is switched on per image by capability
  # detection rather than assumed — see `authtype_supported?`.
  class SessionGitSetup
    AUTHTYPE_MIN_GIT = Gem::Version.new("2.46.0")
    HELPER = "/usr/local/bin/git-credential-aixle-azure"

    def initialize(runtime:, container_id:, session:, logger: Rails.logger)
      @runtime = runtime
      @container_id = container_id
      @session = session
      @logger = logger
    end

    attr_reader :runtime, :container_id, :session

    # Env for the agent process, mirroring cloud_credential_env: only a session
    # that actually holds Azure repositories gets a vending key.
    def self.container_env(session)
      return {} unless AppConfig.enabled?
      return {} unless Array(session.repositories).any? { |r| r.azure_devops? }

      {
        "AIXLE_AZURE_GIT_URL" => Settings.azure_devops&.git_credentials_url.presence ||
          "http://web:4002/azure/git/credentials",
        "AIXLE_AZURE_GIT_KEY" => GitSessionKey.generate(session),
        # The host the helper will answer for. Configurable because api_host is
        # (sovereign clouds), and a helper hardcoded to dev.azure.com would
        # silently refuse every request on such a deployment.
        "AIXLE_AZURE_GIT_HOST" => URI.parse(AppConfig.api_host).host
      }
    end

    # Clone one Azure repository into `target_path`.
    #
    # Returns the runtime's [stdout, stderr, exit_code] triple so the caller's
    # existing retry and failed_repos bookkeeping works unchanged.
    def clone(repository, target_path, uid)
      credential = GitCredentialService.new(session).vend!(repository_id: repository.id)
      header_path = "/tmp/.aixle-azure-#{SecureRandom.hex(8)}"

      # The header travels as a 0600 FILE written through the runtime's tar
      # stream, not as a command argument and not as an exec env option: neither
      # ContainerRuntime implements per-exec env, and argv would put the token in
      # `ps` and in the session's own terminal log. The script reads it into the
      # environment git inherits, deletes it, and unsets it before anything else
      # runs in that shell.
      runtime.write_file(container_id, header_path, authorization_header(credential), mode: 0o600, uid: 0, gid: 0)

      branch = Shellwords.escape(repository.source_branch)
      url = Shellwords.escape(repository.clone_url)
      path = Shellwords.escape(target_path)
      header_file = Shellwords.escape(header_path)

      script = <<~SH.strip
        set -e
        AIXLE_GIT_AUTH_HEADER="$(cat #{header_file})"
        export AIXLE_GIT_AUTH_HEADER
        rm -f #{header_file}
        git --config-env=http.extraheader=AIXLE_GIT_AUTH_HEADER clone --depth=1 --branch=#{branch} #{url} #{path}
        unset AIXLE_GIT_AUTH_HEADER
        #{configure_helper_script(repository, target_path)}
        chown -R #{uid}:#{uid} #{path}
      SH

      runtime.exec(container_id, [ "sh", "-c", script ])
    ensure
      # A failed clone leaves the file behind; remove it rather than trusting the
      # script's own rm to have run.
      begin
        runtime.exec(container_id, [ "sh", "-c", "rm -f #{Shellwords.escape(header_path)}" ]) if header_path
      rescue StandardError
        nil
      end
    end

    # Repository-local configuration so the agent's own `git fetch`/`git push`
    # resolve a credential without any further help.
    #
    # `credential.useHttpPath=true` matters: without it Git matches credentials
    # on host alone, so every Azure repository in the session would resolve to
    # whichever one answered first. The local repository id is written into the
    # config rather than derived from the remote, so rewriting the remote cannot
    # request another repository's credentials.
    def configure_helper_script(repository, target_path)
      path = Shellwords.escape(target_path)
      url = Shellwords.escape(repository.clone_url)
      id = Shellwords.escape(repository.id.to_s)
      helper = Shellwords.escape(HELPER)

      <<~SH.strip
        git -C #{path} config credential.useHttpPath true
        git -C #{path} config credential.#{url}.helper #{helper}
        git -C #{path} config credential.#{url}.aixleRepositoryId #{id}
        git -C #{path} config credential.#{url}.aixleAuthtype #{authtype_supported? ? 1 : 0}
        git -C #{path} config --unset-all http.extraheader || true
      SH
    end

    # Detected, not assumed, and detected per image: the base image installs the
    # distribution's Git without pinning a version, and a custom image can carry
    # anything.
    #
    # The answer is written into each checkout's git config as
    # `credential.<url>.aixleAuthtype`, which is where the helper reads it — the
    # helper cannot probe git itself without recursing, and process env would not
    # survive the agent opening a new shell. `defined?` rather than `||=` so a
    # negative answer is memoized instead of re-probing on every repository.
    def authtype_supported?
      return @authtype_supported if defined?(@authtype_supported)

      @authtype_supported = begin
        out, = runtime.exec(container_id, [ "sh", "-c", "git --version" ])
        version = Array(out).join[/\d+\.\d+(\.\d+)?/]
        version.present? && Gem::Version.new(version) >= AUTHTYPE_MIN_GIT
      rescue StandardError => e
        @logger.warn("[AzureDevops::SessionGitSetup] git capability probe failed: #{e.message}")
        false
      end
    end

    private

    # Microsoft documents `Authorization: Bearer <entra token>` for Entra and
    # Basic for PATs. Reusing GitHub's `user:token@host` URL convention for
    # Entra does not work and would also put the token in the remote.
    def authorization_header(credential)
      case credential.scheme
      when "bearer" then "Authorization: Bearer #{credential.token}"
      when "basic"
        "Authorization: Basic #{Base64.strict_encode64("#{credential.username}:#{credential.token}")}"
      else
        raise Error.new("Unknown Azure credential scheme", code: "credential_action_required")
      end
    end
  end
end
