# frozen_string_literal: true

require "test_helper"

module Web
  module Company
    class FeedbackPolicyTest < ActiveSupport::TestCase
      setup do
        @company = create(:company)
      end

      def policy_for(user)
        FeedbackPolicy.new(BaseContext.new(user, {}, company: @company), :feedback)
      end

      test "every member sends feedback, viewers included; an outsider does not" do
        %i[admin employee viewer].each do |role|
          assert policy_for(create(:user, role, company: @company)).create?, role
        end
        assert_not policy_for(create(:user, :admin, company: create(:company))).create?
      end
    end
  end
end
