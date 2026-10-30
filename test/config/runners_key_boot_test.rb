# frozen_string_literal: true

require "open3"
require "test_helper"

# docs/design/agent-runtimes/DESIGN.md §2: `runners_key` is not required at
# boot. An app without RUNNERS_SECRET_KEY boots and serves everything else, and
# only encrypting or decrypting an op payload fails, with Encryptable's error.
class RunnersKeyBootTest < ActiveSupport::TestCase
  test "the deploy's fail-fast checks do not require RUNNERS_SECRET_KEY" do
    assert_not_includes Rails.root.join("config/initializers/required_env.rb").read, "RUNNERS_SECRET_KEY"
  end

  test "an app without runners_key boots, eager-loaded, and only the payload's encryptor fails" do
    script = <<~RUBY
      Rails.application.eager_load!
      puts "runners_key=\#{Settings.encryption.runners_key.inspect}"
      begin
        Encryptable.encryptor_for("RunnerOperation", :runners_key)
      rescue ArgumentError => e
        puts e.message
      end
    RUBY
    output, status = Open3.capture2e({ "RUNNERS_SECRET_KEY" => "", "RAILS_ENV" => "test" },
                                     Rails.root.join("bin/rails").to_s, "runner", script, chdir: Rails.root.to_s)

    assert status.success?, output
    assert_includes output, "runners_key=nil"
    assert_includes output, "[Encryptable] RunnerOperation encryption key is not set"
  end
end
