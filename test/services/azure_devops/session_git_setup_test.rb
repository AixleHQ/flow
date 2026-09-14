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

    test "the token is never an argument, only a file the script reads" do
      @setup.clone(@repository, "/workspace/repo/api", 1001)

      commands = @runtime.execs.map { |c| Array(c).join(" ") }
      assert commands.any? { |c| c.include?("git --config-env=http.extraheader=AIXLE_GIT_AUTH_HEADER clone") }
      assert commands.none? { |c| c.include?("clone-token") }, "the token must not reach argv"
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
