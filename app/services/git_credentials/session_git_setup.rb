# frozen_string_literal: true

module GitCredentials
  # Everything a container needs to clone, fetch and push its GitHub and GitLab
  # repositories without a token ever sitting in the checkout — the design
  # AzureDevops::SessionGitSetup established, for the other two hosts:
  #
  # - the CLONE authenticates with an `http.extraheader` read from the process
  #   environment through `--config-env`, filled from a 0600 file that is deleted
  #   before git runs; never from argv (the Kubernetes exec API carries argv in its
  #   query string, which the apiserver logs) and never in the remote URL;
  # - every later `git fetch`/`git push` the agent runs goes through the credential
  #   helper, which asks the platform each time.
  class SessionGitSetup
    HELPER = "/workspace/.aixle/git-credential-aixle"
    HELPER_SOURCE = Rails.root.join("docker/base/git/git-credential-aixle")
    HelperNotInstalled = Class.new(StandardError)

    def self.container_env(session)
      return {} unless Array(session.repositories).any? { |r| Vendor::PROVIDERS.include?(r.integration&.provider.to_s) }

      {
        "AIXLE_GIT_CREDENTIALS_URL" => Settings.git.credentials_url,
        "AIXLE_GIT_KEY" => SessionKey.generate(session)
      }
    end

    def initialize(runtime:, container_id:, session:)
      @runtime = runtime
      @container_id = container_id
      @session = session
    end

    # Returns the runtime's [stdout, stderr, exit_code] triple.
    def clone(repository, target_path, uid)
      credential = Vendor.new(@session).vend!(repository_id: repository.id)
      header_path = "/tmp/.aixle-git-#{SecureRandom.hex(8)}"
      header = "Authorization: Basic #{Base64.strict_encode64("#{credential.username}:#{credential.password}")}"
      return not_written("the clone credential") unless @runtime.write_file(@container_id, header_path, header, mode: 0o600, uid: uid, gid: uid)
      return not_written("the git credential helper") unless place_helper(uid)

      url = Vendor.clone_url(repository)
      script = <<~SH.strip
        set -e
        AIXLE_GIT_AUTH_HEADER="$(cat #{Shellwords.escape(header_path)})"
        export AIXLE_GIT_AUTH_HEADER
        rm -f #{Shellwords.escape(header_path)}
        git --config-env=http.extraheader=AIXLE_GIT_AUTH_HEADER clone --depth=1 --branch=#{Shellwords.escape(repository.source_branch)} #{Shellwords.escape(url)} #{Shellwords.escape(target_path)}
        unset AIXLE_GIT_AUTH_HEADER
        #{configure_helper_script(url, repository, target_path)}
        chown -R #{uid}:#{uid} #{Shellwords.escape(target_path)}
      SH
      @runtime.exec(@container_id, [ "sh", "-c", script ])
    ensure
      begin
        @runtime.exec(@container_id, [ "sh", "-c", "rm -f #{Shellwords.escape(header_path)}" ]) if header_path
      rescue StandardError
        nil
      end
    end

    # The same configuration applied to a checkout that already exists and is
    # owned by the session's user (exec runs as root, hence safe.directory): an
    # older clone with a token in its remote gets a clean remote and the helper.
    def reconfigure_script(repository, target_path, uid)
      url = Vendor.clone_url(repository)
      path = Shellwords.escape(target_path)
      git = "git -c safe.directory=#{path} -C #{path}"
      <<~SH.strip
        set -e
        #{git} remote set-url origin #{Shellwords.escape(url)}
        #{configure_helper_script(url, repository, target_path, git: git)}
        chown #{uid}:#{uid} #{path}/.git/config
      SH
    end

    def install_helper!(uid)
      place_helper(uid) || raise(HelperNotInstalled, "could not write the git credential helper into the container")
    end

    private

    def place_helper(uid)
      @runtime.exec(@container_id, [ "sh", "-c", "mkdir -p #{Shellwords.escape(File.dirname(HELPER))}" ])
      @runtime.write_file(@container_id, HELPER, File.read(HELPER_SOURCE), mode: 0o700, uid: uid, gid: uid)
    end

    # A failed clone in the runtime's own shape, so the caller's retry and
    # failed_repos bookkeeping apply to it unchanged.
    def not_written(what) = [ [], [ "could not write #{what} into the container" ], 1 ]

    # `credential.useHttpPath` so two repositories on one host resolve separately;
    # the repository id is recorded here rather than derived from the remote.
    def configure_helper_script(url, repository, target_path, git: "git -C #{Shellwords.escape(target_path)}")
      key = Shellwords.escape(url)
      <<~SH.strip
        #{git} config credential.useHttpPath true
        #{git} config credential.#{key}.helper #{Shellwords.escape(HELPER)}
        #{git} config credential.#{key}.aixleRepositoryId #{Shellwords.escape(repository.id.to_s)}
        #{git} config --unset-all http.extraheader || true
      SH
    end
  end
end
