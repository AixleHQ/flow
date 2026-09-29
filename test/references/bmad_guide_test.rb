# frozen_string_literal: true

require "test_helper"

# The builder recommends BMAD skills from references/bmad-guide.md, written
# against one BMAD release. Skill names change between releases (6.11 renamed
# most of them), so bumping the install pin must come with a re-verified guide.
class BmadGuideTest < ActiveSupport::TestCase
  test "describes the BMAD version the containers install" do
    guide = Rails.root.join("references/bmad-guide.md").read

    assert_includes guide, "bmad-method@#{BmadMethodInjector::BMAD_METHOD_VERSION}",
                    "BMAD pin moved — re-verify references/bmad-guide.md against the new release"
  end
end
