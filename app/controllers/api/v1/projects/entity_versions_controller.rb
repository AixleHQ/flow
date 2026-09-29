# frozen_string_literal: true

module Api
  module V1
    module Projects
      # The Versions tab and the Archived lists: an entity's history, one version
      # with both sides of its diff, revert, and restore from the archive.
      class EntityVersionsController < ApplicationController
        PAGE_SIZE = 20

        # ?versionable_type=Agent&versionable_id=5[&before=<number>] — newest
        # first, PAGE_SIZE at a time; `nextBefore` is null on the last page.
        def index
          record = versionable
          scope = record.entity_versions.includes(:author, :restored_from)
          scope = scope.where(number: ...params[:before].to_i) if params[:before].present?
          page = scope.limit(PAGE_SIZE + 1).to_a
          more = page.size > PAGE_SIZE
          page = page.first(PAGE_SIZE)

          render json: {
            versions: page.map { |v| EntityVersionResource.new(v).to_h },
            nextBefore: more ? page.last.number : nil,
            currentVersionNumber: record.current_version_number
          }
        end

        def show
          render json: EntityVersionDetailResource.new(version).to_h
        end

        def revert
          target = version
          reverted = Versions.revert!(target.versionable, to: target, actor: version_actor,
                                                          base_version: params[:base_version])
          render json: EntityVersionResource.new(reverted).to_h
        end

        def restore
          record = versionable
          ids = Array(params[:enable_trigger_ids]).map(&:to_i)
          restored = Versions.restore!(record, actor: version_actor, enable_trigger_ids: ids)
          render json: EntityVersionResource.new(restored).to_h
        end

        private

        # The five versioned types, each looked up only inside this project —
        # archived rows included, since history and restore are for them too.
        def versionable
          id = params.require(:versionable_id)
          case params.require(:versionable_type)
          when "Workflow" then current_project.workflows.find(id)
          when "Agent" then Agent.for_project(current_project).find(id)
          when "Skill" then Skill.for_project(current_project).find(id)
          when "Tool" then Tool.db_source.where(scope_type: "Project", scope_id: current_project.id).find(id)
          when "MCPServer" then MCPServer.for_project(current_project).find(id)
          else raise ActiveRecord::RecordNotFound
          end
        end

        def version
          @version ||= EntityVersion.where(project_id: current_project.id).find(params[:id])
        end
      end
    end
  end
end
