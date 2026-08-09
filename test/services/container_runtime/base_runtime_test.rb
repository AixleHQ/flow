# frozen_string_literal: true

require "test_helper"

module ContainerRuntime
  class BaseRuntimeTest < ActiveSupport::TestCase
    setup do
      @runtime = BaseRuntime.new
    end

    # -- Lifecycle --

    test "pull_image raises NotImplementedError" do
      assert_raises(NotImplementedError) { @runtime.pull_image("alpine:latest") }
    end

    test "create_container raises NotImplementedError" do
      assert_raises(NotImplementedError) { @runtime.create_container({}) }
    end

    test "start_container raises NotImplementedError" do
      assert_raises(NotImplementedError) { @runtime.start_container("id") }
    end

    test "wait_for_ready raises NotImplementedError" do
      assert_raises(NotImplementedError) { @runtime.wait_for_ready("id") }
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

    # -- Execution --

    test "exec raises NotImplementedError" do
      assert_raises(NotImplementedError) { @runtime.exec("id", [ "echo", "hi" ]) }
    end

    # -- File I/O --

    test "write_file raises NotImplementedError" do
      assert_raises(NotImplementedError) { @runtime.write_file("id", "/path", "content") }
    end

    test "read_file raises NotImplementedError" do
      assert_raises(NotImplementedError) { @runtime.read_file("id", "/path") }
    end

    # -- Introspection --

    test "resolve_container raises NotImplementedError" do
      assert_raises(NotImplementedError) { @runtime.resolve_container("id") }
    end

    test "container_identifier raises NotImplementedError" do
      assert_raises(NotImplementedError) { @runtime.container_identifier("container") }
    end

    test "container_status raises NotImplementedError" do
      assert_raises(NotImplementedError) { @runtime.container_status("id") }
    end

    test "wait_container raises NotImplementedError" do
      assert_raises(NotImplementedError) { @runtime.wait_container("id") }
    end

    test "container_logs raises NotImplementedError" do
      assert_raises(NotImplementedError) { @runtime.container_logs("id") }
    end

    # -- Tar extraction --
    #
    # A tar header's name field is 100 bytes. Longer paths are carried out-of-band:
    # GNU/busybox tar (what `KubernetesRuntime#copy_from` runs) writes a `L`
    # long-name entry, Docker's Go writer a PAX `x` header — and in both cases the
    # following real entry's name is truncated/garbled. Matching entries on the
    # requested basename therefore dropped every long-named file, read_file returned
    # nil, and session outputs silently never became assets (Cyrillic titles at 2
    # bytes/char overflow at ~40 characters).

    test "extract_from_tar returns the entry when the name fits the tar header" do
      tar = tar_bytes([ [ "workspace/outputs/report.md", "SHORT" ] ])

      assert_equal "SHORT", @runtime.send(:extract_from_tar, tar, "report.md")
    end

    test "extract_from_tar reads a GNU long-name entry whose real header name is truncated" do
      long_path = "workspace/outputs/report dir/#{'a' * 80} final report.md"
      tar = tar_bytes([
        [ "././@LongLink", "#{long_path}\0", "L" ],
        [ long_path.byteslice(0, 100), "LONG" ]
      ])

      assert_equal "LONG", @runtime.send(:extract_from_tar, tar, File.basename(long_path))
    end

    test "extract_from_tar reads a PAX-prefixed entry with a garbled real header name" do
      tar = tar_bytes([
        [ "PaxHeaders.0/report", "30 path=workspace/outputs/x.md\n", "x" ],
        [ "        7  2026   .md", "PAX" ]
      ])

      assert_equal "PAX", @runtime.send(:extract_from_tar, tar, "Итоговый отчет.md")
    end

    test "extract_from_tar prefers the requested basename over the first entry" do
      tar = tar_bytes([
        [ "workspace/outputs/other.md", "OTHER" ],
        [ "workspace/outputs/wanted.md", "WANTED" ]
      ])

      assert_equal "WANTED", @runtime.send(:extract_from_tar, tar, "wanted.md")
    end

    test "extract_from_tar returns nil when the tar carries no file entry" do
      tar = tar_bytes([ [ "workspace/outputs/", "", "5" ] ])

      assert_nil @runtime.send(:extract_from_tar, tar, "report.md")
    end

    private

    # Builds raw tar bytes entry by entry so each header layout (regular file, GNU
    # `L` long name, PAX `x`) is spelled out in the test rather than depending on
    # whichever tar binary the environment ships.
    def tar_bytes(entries)
      buffer = +"".b

      entries.each do |name, content, typeflag|
        body = content.to_s.b
        header = Gem::Package::TarHeader.new(
          name: name, mode: 0o644, size: body.bytesize, prefix: "",
          uid: 0, gid: 0, typeflag: (typeflag || "0"), mtime: Time.now
        )
        buffer << header.to_s
        buffer << body
        padding = (512 - (body.bytesize % 512)) % 512
        buffer << ("\0" * padding)
      end

      buffer << ("\0" * 1024)
      buffer
    end
  end
end
