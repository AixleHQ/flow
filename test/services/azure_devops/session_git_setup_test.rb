# frozen_string_literal: true

require "test_helper"

module AzureDevops
  # Cloning an Azure repository into a session container.
  #
  # The credential travels as a file rather than as an argument, which is the
  # only part of this worth being careful about: argv would put the token in
  # `ps` and in the session's own terminal log.
  class SessionGitSetupTest < ActiveSupport::TestCase
    setup do
      with_azure_devops_enabled
      @integration = create(:integration, :azure_devops, :active)
      @project = @integration.project
      @repository = create(:repository, :azure_devops, integration: @integration, scope: @project)
      @session = create(:terminal_session, :running, project: @project, user: @project.owner)
      @session.repositories << @repository
      stub_azure_token(tenant_id: @integration.azure_devops_installation.tenant_id, token: "clone-token")

      @runtime = ContainerRuntime::FakeRuntime.new
      @setup = SessionGitSetup.new(runtime: @runtime, container_id: "c1", session: @session)
    end

    # `exec` runs as the container's own user, so a root-owned 0600 file is one
    # the clone script can neither read — "cat: Permission denied", an empty
    # workspace and a failed session — nor delete, leaving the credential in
    # /tmp afterwards. It is owned by the session's uid for both reasons.
    test "the credential file belongs to the user that has to read it" do
      @setup.clone(@repository, "/workspace/repo/api", 1001)

      path = @runtime.fs.keys.find { |k| k.include?("aixle-azure") }
      assert path, "the authorization header should be written as a file"

      attrs = @runtime.file_attributes(path)
      assert_equal 1001, attrs[:uid]
      assert_equal 1001, attrs[:gid]
      assert_equal 0o600, attrs[:mode]
    end

    # Baked into the agent image, the helper made the platform and every image a
    # matched pair: an image predating it produced a checkout configured to call
    # a file that was not there, and every push failed with "could not read
    # Username" with nothing pointing at the image.
    test "the credential helper is installed into the session, not assumed present" do
      @setup.clone(@repository, "/workspace/repo/api", 1001)

      helper = @runtime.fs[SessionGitSetup::HELPER]
      assert helper, "the helper itself must be written into the container"
      assert_includes helper, "AIXLE_AZURE_GIT_KEY", "the real script, not a placeholder"

      attrs = @runtime.file_attributes(SessionGitSetup::HELPER)
      assert_equal 0o700, attrs[:mode]
      assert_equal 1001, attrs[:uid]

      commands = @runtime.execs.map { |c| Array(c).join(" ") }
      assert commands.any? { |c| c.include?("config credential.") && c.include?(SessionGitSetup::HELPER) },
             "the checkout must point at the helper that was just installed"
    end

    # Only sessions that actually clone an Azure repository get it. In the image
    # every agent carried it whether or not it would ever speak to Azure.
    test "a session with no Azure repository never receives the helper" do
      other = SessionGitSetup.new(runtime: @runtime, container_id: "c1", session: @session)
      assert_nil @runtime.fs[SessionGitSetup::HELPER], "nothing is installed before a clone"

      other.clone(@repository, "/workspace/repo/api", 1001)

      assert @runtime.fs[SessionGitSetup::HELPER], "installing it is part of cloning, not of starting a session"
    end

    test "the token is never an argument, only a file the script reads" do
      @setup.clone(@repository, "/workspace/repo/api", 1001)

      commands = @runtime.execs.map { |c| Array(c).join(" ") }
      assert commands.any? { |c| c.include?("git --config-env=http.extraheader=AIXLE_GIT_AUTH_HEADER clone") }
      assert commands.none? { |c| c.include?("clone-token") }, "the token must not reach argv"
    end

    # The runtime answers false for a write it could not complete. Unchecked, the
    # clone died on `cat` of a missing file, or succeeded with no helper and left
    # every later fetch and push to fail.
    test "a credential or helper that could not be written fails the clone before git runs" do
      [ /aixle-azure-/, SessionGitSetup::HELPER ].each do |unwritable|
        runtime = ContainerRuntime::FakeRuntime.new.fail_write(unwritable)
        setup = SessionGitSetup.new(runtime: runtime, container_id: "c1", session: @session)

        _stdout, stderr, exit_code = setup.clone(@repository, "/workspace/repo/api", 1001)

        assert_equal 1, exit_code
        assert_match(/could not write/, Array(stderr).join)
        assert runtime.execs.none? { |c| Array(c).join(" ").include?("clone --depth=1") }, "git ran without #{unwritable}"
      end
    end

    test "the credential file is removed even when the clone fails" do
      @runtime.fail_exec("git --config-env", stderr: "fatal: repository not found", exit_code: 128)

      @setup.clone(@repository, "/workspace/repo/api", 1001)

      path = @runtime.fs.keys.find { |k| k.include?("aixle-azure") }
      assert @runtime.execs.map { |c| Array(c).join(" ") }.any? { |c| c.start_with?("sh -c rm -f") && c.include?(path) },
             "a failed clone must not leave the credential behind"
    end
  end
end
