# frozen_string_literal: true

require "test_helper"
require "open3"

module GitCredentials
  # The wrapper runs inside agent containers, so it is exercised as the script it
  # is: real bash and git, checkouts configured the way SessionGitSetup configures
  # them, a stand-in for the platform's credential helper that answers with the
  # repository id a checkout records, and a stand-in for the real gh that reports
  # the token it was handed.
  class GhWrapperTest < ActiveSupport::TestCase
    setup do
      @dir = Dir.mktmpdir("gh-wrapper")
      @root = File.join(@dir, "repo")
      FileUtils.mkdir_p([ @root, bin_dir("wrapper"), bin_dir("real") ])
      FileUtils.cp(Rails.root.join("docker/base/git/gh-aixle"), wrapper)
      FileUtils.chmod(0o755, wrapper)
      write_executable(File.join(bin_dir("real"), "gh"), %(#!/bin/bash\necho "token=${GH_TOKEN:-none} args=$*"\n))
      write_executable(helper, <<~SH)
        #!/bin/bash
        [ "${1:-}" = get ] || { cat >/dev/null; exit 0; }
        while IFS='=' read -r k v; do [ -z "$k" ] && break; case $k in host) h=$v;; path) p=$v;; esac; done
        id="$(git config --get "credential.https://$h/$p.aixleRepositoryId")" || exit 0
        printf 'username=x-access-token\\npassword=ghs-for-%s\\n' "$id"
      SH
    end

    teardown { FileUtils.rm_rf(@dir) }

    test "a call inside a checkout carries that repository's credential" do
      checkout("site", "acme/site", 31)
      api = checkout("api", "acme/api", 32)

      assert_equal "token=ghs-for-32 args=pr list", gh("pr", "list", chdir: api).first.strip
    end

    test "-R, GH_REPO and a gh api repos path each name the repository from outside any checkout" do
      checkout("site", "acme/Site", 31)
      checkout("api", "acme/api", 32)

      assert_equal "token=ghs-for-31 args=pr list -R acme/site", gh("pr", "list", "-R", "acme/site").first.strip
      assert_equal "token=ghs-for-31 args=pr view 5 --repo=https://github.com/acme/Site.git",
                   gh("pr", "view", "5", "--repo=https://github.com/acme/Site.git").first.strip
      assert_equal "token=ghs-for-32 args=pr list", gh("pr", "list", env: { "GH_REPO" => "acme/api" }).first.strip
      assert_equal "token=ghs-for-32 args=api -X POST /repos/acme/api/merges",
                   gh("api", "-X", "POST", "/repos/acme/api/merges").first.strip
    end

    test "outside any checkout the only GitHub checkout is the default, and two are never guessed between" do
      checkout("site", "acme/site", 31)
      assert_equal "token=ghs-for-31 args=pr list", gh("pr", "list").first.strip

      checkout("api", "acme/api", 32)
      stdout, stderr, = gh("pr", "list")
      assert_equal "token=none args=pr list", stdout.strip
      assert_match(/pass -R <owner>\/<repo>/, stderr)
    end

    test "a repository that is not attached to the session gets no credential" do
      checkout("site", "acme/site", 31)

      stdout, stderr, = gh("pr", "list", "-R", "someone/else")

      assert_equal "token=none args=pr list -R someone/else", stdout.strip
      assert_match(/no platform credential/, stderr)
    end

    test "a session with no GitHub checkout runs gh untouched and says nothing" do
      stdout, stderr, = gh("pr", "list")

      assert_equal "token=none args=pr list", stdout.strip
      assert_empty stderr
    end

    test "the agent base image installs the wrapper ahead of the real gh" do
      assert_match %r{^COPY git/gh-aixle /usr/local/bin/gh$}, Rails.root.join("docker/base/Dockerfile").read
    end

    test "a token the caller set, or a container with no session key, passes straight through" do
      checkout("site", "acme/site", 31)

      assert_equal "token=mine args=pr list", gh("pr", "list", env: { "GH_TOKEN" => "mine" }).first.strip
      assert_equal "token=none args=pr list", gh("pr", "list", env: { "AIXLE_GIT_KEY" => nil }).first.strip
    end

    private

    def gh(*args, chdir: @dir, env: {})
      Open3.capture3(git_env.merge(
        "PATH" => "#{bin_dir('wrapper')}:#{bin_dir('real')}:#{ENV.fetch('PATH')}",
        "AIXLE_REPO_ROOT" => @root,
        "AIXLE_GIT_KEY" => "session-key",
        "GH_TOKEN" => nil, "GITHUB_TOKEN" => nil, "GH_REPO" => nil
      ).merge(env), wrapper, *args, chdir: chdir)
    end

    def checkout(name, full_name, repository_id)
      path = File.join(@root, name)
      url = "https://github.com/#{full_name}.git"
      git("init", "-q", path)
      git("-C", path, "remote", "add", "origin", url)
      git("-C", path, "config", "credential.useHttpPath", "true")
      git("-C", path, "config", "credential.#{url}.helper", helper)
      git("-C", path, "config", "credential.#{url}.aixleRepositoryId", repository_id.to_s)
      path
    end

    def git(*args) = system(git_env, "git", *args, exception: true)

    def git_env = { "GIT_CONFIG_GLOBAL" => File::NULL, "GIT_CONFIG_NOSYSTEM" => "1" }

    def write_executable(path, content)
      File.write(path, content)
      FileUtils.chmod(0o755, path)
    end

    def bin_dir(name) = File.join(@dir, name)

    def wrapper = File.join(bin_dir("wrapper"), "gh")

    def helper = File.join(@dir, "git-credential-test")
  end
end
