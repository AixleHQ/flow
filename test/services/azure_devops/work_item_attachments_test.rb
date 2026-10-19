# frozen_string_literal: true

require "test_helper"

module AzureDevops
  # Contract tests: WorkItemService's files against Azure's work item, comment
  # and attachment payloads. FakeAzureDevops::WorkItemService returns the shapes
  # pinned here.
  class WorkItemAttachmentsTest < ActiveSupport::TestCase
    setup do
      with_azure_devops_enabled
      resolve_hosts_publicly!
      @integration = create(:integration, :azure_devops, :active)
      stub_azure_token(tenant_id: @integration.azure_devops_installation.tenant_id)
      @org = CredentialProvider.client_for(@integration).last.organization
      @project = @integration.azure_project_id
      @service = WorkItemService.new(@integration)
    end

    def json(body) = { status: 200, headers: { "Content-Type" => "application/json" }, body: body.to_json }

    def stub_item(fields: {}, relations: [])
      stub_request(:get, %r{/_apis/wit/workitems/11\?}).to_return(
        json(id: 11, rev: 2, fields: { "System.TeamProject" => "Customer Platform", "System.Title" => "t" }.merge(fields),
             relations: relations)
      )
    end

    def stub_comments(comments)
      stub_request(:get, %r{/_apis/wit/workItems/11/comments\?}).to_return(json(comments: comments, count: comments.size))
    end

    test "files are the AttachedFile relations and this organization's images in fields and comments" do
      attached = "6c4e1a2b-0000-4000-8000-000000000001"
      inline = "6c4e1a2b-0000-4000-8000-000000000002"
      in_comment = "6c4e1a2b-0000-4000-8000-000000000003"
      foreign = "6c4e1a2b-0000-4000-8000-000000000004"
      stub_item(
        fields: { "System.Description" => %(<div><img src="https://dev.azure.com/#{@org}/#{@project}/_apis/wit/attachments/#{inline}?fileName=steps.png"></div>) },
        relations: [
          { rel: "AttachedFile", url: "https://dev.azure.com/#{@org}/#{@project}/_apis/wit/attachments/#{attached}",
            attributes: { name: "trace.log", resourceSize: 42, resourceCreatedDate: "2026-10-01T10:00:00Z" } },
          { rel: "ArtifactLink", url: "vstfs:///Git/PullRequestId/x" }
        ]
      )
      stub_comments([
        { id: 5, text: %(<img src="https://#{@org}.visualstudio.com/#{@project}/_apis/wit/attachments/#{in_comment}?fileName=after.png">) },
        { id: 6, text: %(<img src="https://dev.azure.com/someone-else/p/_apis/wit/attachments/#{foreign}?fileName=x.png">) }
      ])

      files = @service.attachments(11)

      assert_equal [ [ attached, "trace.log", 42, :attached, nil ],
                     [ inline, "steps.png", nil, :embedded, { "kind" => "description" } ],
                     [ in_comment, "after.png", nil, :embedded, { "kind" => "comment", "id" => "5" } ] ],
                   files.map { |f| f.values_at(:id, :name, :size, :origin, :location) }
    end

    test "a download is built from the guid on this organization's path, with the connection's token" do
      guid = "6c4e1a2b-0000-4000-8000-000000000001"
      stub = stub_request(:get, "#{AZURE_API_HOST}/#{@org}/#{@project}/_apis/wit/attachments/#{guid}")
               .with(query: { "download" => "true", "api-version" => "7.1" }, headers: { "Authorization" => "Bearer azure-access-token" })
               .to_return(status: 200, body: "trace")
      io = StringIO.new

      @service.download_attachment(guid, io: io, max_bytes: 1.megabyte)

      assert_requested stub
      assert_equal "trace", io.string
    end

    test "an upload is linked to the work item as an AttachedFile" do
      guid = "6c4e1a2b-0000-4000-8000-000000000009"
      url = "https://dev.azure.com/#{@org}/#{@project}/_apis/wit/attachments/#{guid}"
      upload = stub_request(:post, "#{AZURE_API_HOST}/#{@org}/#{@project}/_apis/wit/attachments")
                 .with(query: { "fileName" => "a b.txt", "api-version" => "7.1" }, headers: { "Content-Type" => "application/octet-stream" })
                 .to_return(json(id: guid, url: url))
      link = stub_request(:patch, %r{/_apis/wit/workitems/11\?})
               .with { |r| JSON.parse(r.body).first.dig("value", "rel") == "AttachedFile" && JSON.parse(r.body).first.dig("value", "url") == url }
               .to_return(json(id: 11, rev: 3, fields: {}))
      file = Trackers::UploadFile.new(io: StringIO.new("a"), filename: "a b.txt", content_type: "text/plain", size: 1, sha256: "x")

      result = @service.upload_attachment(11, file)

      assert_requested upload
      assert_requested link
      assert_equal [ guid, "a b.txt" ], result.values_at(:id, :name)
    end
  end
end
