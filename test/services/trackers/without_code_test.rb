# frozen_string_literal: true

require "test_helper"

class Trackers::WithoutCodeTest < ActiveSupport::TestCase
  test "a mention inside markdown, Jira or HTML code is cut out; one in prose stays" do
    {
      "a `@aixle` b" => false,
      "a ``@aixle `x` `` b" => false,
      "```\n@aixle\n```" => false,
      "~~~\n@aixle\n~~~" => false,
      "{code:ruby}\n@aixle\n{code}" => false,
      "{noformat}@aixle{noformat}" => false,
      "{{@aixle}}" => false,
      "<pre>@aixle</pre>" => false,
      "<p><code>@aixle</code></p>" => false,
      "hey @aixle, look at `this`" => true
    }.each do |text, mentions|
      assert_equal mentions, Trackers.without_code(text).include?("@aixle"), text
    end
  end
end
