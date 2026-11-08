# frozen_string_literal: true

module Sessions
  class Snapshot
    # One shell script that reads every requested part (Parts::REGISTRY), and the parser
    # of its output.
    #
    # Each part's output sits between a header line and a footer line that carries the
    # fragment's exit status:
    #
    #   <marker> scrollback
    #   …what capture-pane printed…
    #   <marker> end 0
    #
    # The marker carries a random nonce per read. The pane is mostly the agent's own work,
    # and an agent that greps this file would otherwise print a fixed marker into the very
    # output it delimits.
    class Command
      MARKER_PREFIX = "__aixle_snapshot_"

      attr_reader :parts, :marker

      def initialize(parts, nonce: SecureRandom.hex(8))
        @parts = parts.map { |name| Parts.fetch(name).name }.uniq
        @marker = "#{MARKER_PREFIX}#{nonce}__"
      end

      # The `echo` before the footer puts it on its own line even after output that does
      # not end in a newline; the parser takes that newline back off.
      def argv
        script = parts.map do |name|
          "echo '#{marker} #{name}'; #{Parts.fetch(name).script}; s=$?; echo; echo \"#{marker} end $s\""
        end
        [ "/bin/sh", "-c", script.join("; ") ]
      end

      # @return [Hash{Symbol => String}] the raw output of each part whose fragment exited 0
      def parse(stdout)
        pattern = /^#{Regexp.escape(marker)} (\w+)\n(.*?)\n#{Regexp.escape(marker)} end (\d+)$/m
        # Invalid UTF-8 is replaced rather than raised on: a pane can end in the middle of a
        # multibyte character (Sessions::ScreenDigest.lines does the same).
        text = stdout.to_s.dup.force_encoding(Encoding::UTF_8).scrub
        text.scan(pattern).each_with_object({}) do |(name, output, status), read|
          name = name.to_sym
          read[name] = output if parts.include?(name) && status == "0"
        end
      end
    end
  end
end
