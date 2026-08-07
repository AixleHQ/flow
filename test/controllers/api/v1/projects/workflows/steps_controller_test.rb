# frozen_string_literal: true

require "test_helper"

module Api
  module V1
    module Projects
      module Workflows
        class StepsControllerTest < ActionController::TestCase
          setup do
            @company = create(:company)
            @user = create(:user, :onboarding_completed, company: @company)
            @project = create(:project, company: @company, owner: @user)
            @workflow = create(:workflow, scope: @project)
            @step = create(:step, workflow: @workflow, position: 1)
            sign_in @user
          end

          test "index returns steps json" do
            get :index, params: { project_id: @project.id, workflow_id: @workflow.id }

            assert_response :success
          end

          test "show returns step json" do
            get :show, params: { project_id: @project.id, workflow_id: @workflow.id, id: @step.id }

            assert_response :success
          end

          test "create returns created step" do
            post :create, params: {
              project_id: @project.id,
              workflow_id: @workflow.id,
              step: {
                name: "p_step",
                instructions: "Run",
                position: 2
              }
            }

            assert_response :created
          end

          test "update returns step json" do
            patch :update, params: {
              project_id: @project.id,
              workflow_id: @workflow.id,
              id: @step.id,
              step: { instructions: "U" }
            }

            assert_response :success
          end

          # The builder's resource pickers PATCH these two lists and nothing else
          # writes them, so an id dropped from the permit list would fail silently:
          # the request still succeeds and the selection just never persists.
          test "update persists the repository and asset selections the builder sends" do
            repository = create(:repository, scope: @project)
            asset = create(:asset, scope: @project)

            patch :update, params: {
              project_id: @project.id,
              workflow_id: @workflow.id,
              id: @step.id,
              step: { repository_ids: [ repository.id ], asset_ids: [ asset.id ] }
            }, as: :json

            assert_response :success
            @step.reload
            assert_equal [ repository.id ], @step.repository_ids
            assert_equal [ asset.id ], @step.asset_ids
          end

          test "destroy removes step" do
            delete :destroy, params: {
              project_id: @project.id,
              workflow_id: @workflow.id,
              id: @step.id
            }

            assert_response :no_content
          end

          test "reorder returns ok" do
            s2 = create(:step, workflow: @workflow, position: 2)

            patch :reorder, params: {
              project_id: @project.id,
              workflow_id: @workflow.id,
              positions: { @step.id.to_s => "1", s2.id.to_s => "2" }
            }

            assert_response :success
          end
        end
      end
    end
  end
end
