# frozen_string_literal: true

# Tags decide when a test runs. config/test_tags.json defines each tag and its rule; this lets a
# test or a test class carry one, and leaves out the tests of the tags TEST_EXCLUDE_TAGS names
# (CI sets it on a pull request, see bin/test-tags). docs/testing.md §9.
#
#   class SchemaParityTest < ActiveSupport::TestCase
#     tags :schema_parity            # every test of the class
#
#     tag :schema_parity             # the next test only
#     test "..." do ... end
#   end
#
# Minitest has no tags of its own and the maintained-looking gems are not (minitest-tagz was last
# released in 2019 and requires minitest ~> 5), so this is the small piece the runner needs: a
# declaration, and a filter in `runnable_methods`, which is where Minitest picks a class's tests.
module TestTagging
  extend ActiveSupport::Concern

  included do
    class_attribute :class_test_tags, instance_accessor: false, default: [].freeze
    class_attribute :method_test_tags, instance_accessor: false, default: {}.freeze
  end

  class_methods do
    # Tags every test of this class (and of its subclasses).
    def tags(*names)
      names = validated_test_tags(names)
      self.class_test_tags = (class_test_tags + names).uniq.freeze
    end

    # Tags the next test defined in this class.
    def tag(*names)
      @pending_test_tags = validated_test_tags(names)
    end

    def method_added(name)
      super
      return unless @pending_test_tags && name.to_s.start_with?("test_")

      self.method_test_tags = method_test_tags.merge(name.to_s => @pending_test_tags).freeze
      @pending_test_tags = nil
    end

    def test_tags_of(method_name)
      (class_test_tags + method_test_tags.fetch(method_name.to_s, [])).uniq
    end

    def runnable_methods
      excluded = TestTags.excluded_by_environment
      return super if excluded.empty?

      super.reject { |method_name| (test_tags_of(method_name) & excluded).any? }
    end

    private

    def validated_test_tags(names)
      names = names.flatten.map(&:to_s)
      TestTags.load.validate!(names)
      names
    end
  end
end

ActiveSupport::TestCase.include(TestTagging)
