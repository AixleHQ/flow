# frozen_string_literal: true

module SafeRelativePath
  def self.valid?(path)
    path.is_a?(String) && path.present? && !path.start_with?("/", "~") && !path.match?(/[\\[:cntrl:]]/) &&
      path.split("/", -1).none? { |part| part.empty? || part == "." || part == ".." }
  end

  # The path under `root`, or nil when `relative` would land anywhere else.
  def self.join(root, relative)
    return nil unless valid?(relative)

    target = File.expand_path(relative, root)
    target if target.start_with?("#{File.expand_path(root)}/")
  end
end
