# frozen_string_literal: true

require "test_helper"

module ContainerRuntime
  class BaseRuntimeTest < ActiveSupport::TestCase
    setup do
      @runtime = BaseRuntime.new
    end

    test "pull_image raises NotImplementedError" do
      assert_raises(NotImplementedError) { @runtime.pull_image("alpine:latest") }
    end

    test "create_container raises NotImplementedError" do
      assert_raises(NotImplementedError) { @runtime.create_container({}) }
    end

    test "start_container raises NotImplementedError" do
      assert_raises(NotImplementedError) { @runtime.start_container("id") }
    end

    test "exec raises NotImplementedError" do
      assert_raises(NotImplementedError) { @runtime.exec("id", [ "echo", "hi" ]) }
    end

    test "copy_from raises NotImplementedError" do
      assert_raises(NotImplementedError) { @runtime.copy_from("id", "/path") }
    end

    test "copy_to raises NotImplementedError" do
      assert_raises(NotImplementedError) { @runtime.copy_to("id", "/path", "content") }
    end

    test "store_file raises NotImplementedError" do
      assert_raises(NotImplementedError) { @runtime.store_file("id", "/path", "content") }
    end

    test "read_file raises NotImplementedError" do
      assert_raises(NotImplementedError) { @runtime.read_file("id", "/path") }
    end

    test "wait_container raises NotImplementedError" do
      assert_raises(NotImplementedError) { @runtime.wait_container("id") }
    end

    test "container_logs raises NotImplementedError" do
      assert_raises(NotImplementedError) { @runtime.container_logs("id") }
    end

    test "stop_container raises NotImplementedError" do
      assert_raises(NotImplementedError) { @runtime.stop_container("id") }
    end

    test "remove_container raises NotImplementedError" do
      assert_raises(NotImplementedError) { @runtime.remove_container("id") }
    end

    test "remove_image is no-op by default" do
      assert_nil @runtime.remove_image("alpine:latest")
    end

    test "wait_for_ready raises NotImplementedError" do
      assert_raises(NotImplementedError) { @runtime.wait_for_ready("id") }
    end

    test "resolve_container raises NotImplementedError" do
      assert_raises(NotImplementedError) { @runtime.resolve_container("id") }
    end

    test "container_identifier raises NotImplementedError" do
      assert_raises(NotImplementedError) { @runtime.container_identifier("container") }
    end
  end
end
