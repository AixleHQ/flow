# frozen_string_literal: true

# In-memory fake for PublicRepositoryService (testing doctrine R3: "one
# canonical fake per boundary", docs/testing.md). Callers stub the constructor
# — `PublicRepositoryService.resolve` delegates to `new.resolve` — and hand back
# a fake instead of reaching api.github.com:
#
#   fake = FakePublicRepositoryService.new
#   PublicRepositoryService.stubs(:new).returns(fake)
#   ...
#   assert_equal "rails/rails", fake.calls.last
#
# The canned Result is the exact shape the WebMock contract test in
# test/services/public_repository_service_test.rb pins the real adapter to (R4).
class FakePublicRepositoryService
  DEFAULT_RESULT = PublicRepositoryService::Result.new(
    provider: "github",
    full_name: "rails/rails",
    default_branch: "main",
    clone_url: "https://github.com/rails/rails.git",
    description: "Ruby on Rails"
  ).freeze

  # Every resolved input, in order.
  attr_reader :calls

  # @param result [PublicRepositoryService::Result] what #resolve returns
  # @param error [Exception, nil] raised instead (use a real
  #   PublicRepositoryService::Error subclass to exercise caller rescue branches)
  def initialize(result: DEFAULT_RESULT, error: nil)
    @result = result
    @error = error
    @calls = []
  end

  def resolve(input)
    @calls << input
    raise @error if @error

    @result
  end
end
