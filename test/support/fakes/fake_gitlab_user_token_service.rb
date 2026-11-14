# frozen_string_literal: true

# In-memory fake for Gitlab::UserTokenService — the calls made with a person's own
# GitLab token. The canned shapes are the ones
# test/services/gitlab/user_token_service_test.rb pins the real adapter to.
module FakeGitlab
  class UserTokenService
    DEFAULT_PROFILE = { id: 456, username: "lab-user", name: "Lab User", avatar_url: "https://a.test/456",
                        commit_email: "456-lab-user@users.noreply.gitlab.com" }.freeze

    attr_reader :calls

    # @param access [Hash{String => Integer, nil}] access level per project path; a path
    #   not listed has Maintainer (40)
    # @param access_error [Exception, nil] raised by #project_access when set
    # @param profile [Hash] what #user returns
    # @param profile_error [Exception, nil] raised by #user when set
    def initialize(access: {}, access_error: nil, profile: DEFAULT_PROFILE, profile_error: nil)
      @access = access
      @access_error = access_error
      @profile = profile.dup
      @profile_error = profile_error
      @calls = []
    end

    def user(token)
      @calls << { method: :user, token: token }
      raise @profile_error if @profile_error

      @profile.dup
    end

    def project_access(token, full_path, user_id: nil)
      @calls << { method: :project_access, token: token, full_path: full_path, user_id: user_id }
      raise @access_error if @access_error

      @access.fetch(full_path, 40)
    end

    def called?(method_name) = @calls.any? { |call| call[:method] == method_name }

    def calls_to(method_name) = @calls.select { |call| call[:method] == method_name }
  end
end
