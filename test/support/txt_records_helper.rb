# frozen_string_literal: true

# Domain verification reads DNS, and a test must not. Dns::TxtLookup is the one
# place this application resolves a name, so its resolver is swapped for a hash
# of what the world would answer.
module TxtRecordsHelper
  def published_txt_records(records = {})
    @published_txt_records = records.transform_keys(&:to_s)
    Dns::TxtLookup.resolver = ->(host) { Array(@published_txt_records[host.to_s]) }
  end

  def teardown
    # Nothing else may reach a nameserver, including the test that runs next.
    Dns::TxtLookup.resolver = nil
    super
  end
end

ActiveSupport::TestCase.include(TxtRecordsHelper)
