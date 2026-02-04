# Story 7.5: Select MCP Servers for Session

Status: ready-for-dev

## Story

As a user,
I want to select which MCP servers are available when starting a session,
So that I control what external tools the agent can access.

## Acceptance Criteria

1. Session start form shows available MCP servers (company + project merged)
2. Internal "Palad Tools" always included if custom tools selected (from 7.2)
3. Can select 0..N custom MCP servers
4. Selected servers saved to `session_mcp_servers` join table
5. MCP config injected into agent container with all selected servers

## Tasks

### Task 1: SessionMcpServer Join Table & Model (AC: 4)

- [ ] Create migration for `session_mcp_servers` join table
- [ ] Create `SessionMcpServer` model
- [ ] Add associations to `TerminalSession`
- [ ] Add `available_mcp_servers` method

```ruby
# Migration
create_table :session_mcp_servers do |t|
  t.references :terminal_session, null: false, foreign_key: true
  t.references :mcp_server, null: false, foreign_key: true
  t.timestamps
end
add_index :session_mcp_servers, [:terminal_session_id, :mcp_server_id],
          unique: true, name: 'idx_session_mcp_servers_unique'

# Model: app/models/session_mcp_server.rb
class SessionMcpServer < ApplicationRecord
  belongs_to :terminal_session
  belongs_to :mcp_server

  validates :mcp_server_id, uniqueness: { scope: :terminal_session_id }
end

# Update TerminalSession
class TerminalSession < ApplicationRecord
  has_many :session_mcp_servers, dependent: :destroy
  has_many :mcp_servers, through: :session_mcp_servers

  # Returns all MCP servers for this session
  # Includes: selected custom servers + internal Palad server (if tools selected)
  def available_mcp_servers
    servers = mcp_servers.enabled.to_a

    # Add internal Palad server config if any tools are selected
    if tools.any?
      servers << build_internal_mcp_server
    end

    servers
  end

  private

  def build_internal_mcp_server
    OpenStruct.new(
      name: 'palad-tools',
      display_name: 'Palad Tools',
      url: ENV.fetch('MCP_SERVER_URL', 'http://web:3000/action_mcp'),
      transport: 'sse',
      headers: { 'X-Session-Key' => mcp_key },
      kind: 'internal'
    )
  end
end
```

### Task 2: Backend — Available MCP Servers Endpoint (AC: 1)

- [ ] Create `GET /api/v1/projects/:project_id/available_mcp_servers`
- [ ] Return merged list using `McpServer.merged_for_project`
- [ ] Filter to custom servers only (internal is auto-added)

```ruby
# app/controllers/api/v1/projects/available_mcp_servers_controller.rb
class Api::V1::Projects::AvailableMcpServersController < Api::V1::BaseController
  def index
    servers = McpServer.merged_for_project(project).select(&:custom?)
    render json: { items: servers.map { |s| serialize_server(s) } }
  end

  private

  def serialize_server(server)
    {
      id: server.id,
      name: server.name,
      displayName: server.display_name,
      url: server.url,
      transport: server.transport,
      description: server.description,
      scopeIndicator: server.scope_indicator,
      enabled: server.enabled
    }
  end
end
```

### Task 3: Backend — Accept mcp_server_ids on Session Create (AC: 3, 4)

- [ ] Update `TerminalSessionsController#create` to accept `mcp_server_ids`
- [ ] Create `session_mcp_servers` records
- [ ] Validate server_ids are valid for project

```ruby
# In terminal_sessions_controller.rb
def create
  @session = TerminalSession.new(session_params)
  @session.user = current_user

  if @session.save
    create_session_tools(params[:tool_ids]) if params[:tool_ids].present?
    create_session_mcp_servers(params[:mcp_server_ids]) if params[:mcp_server_ids].present?
    render json: { data: serialize_session(@session) }, status: :created
  else
    render json: { errors: @session.errors }, status: :unprocessable_entity
  end
end

private

def create_session_mcp_servers(server_ids)
  available_ids = McpServer.merged_for_project(@session.project).pluck(:id)
  valid_ids = server_ids.map(&:to_i) & available_ids

  valid_ids.each do |server_id|
    @session.session_mcp_servers.create!(mcp_server_id: server_id)
  end
end
```

### Task 4: Backend — Inject MCP Config into Container (AC: 5)

- [ ] Update `ContainerService` to build full MCP config
- [ ] Include all selected servers + internal if tools selected
- [ ] Generate MCP config JSON for agent

```ruby
# In ContainerService
def build_mcp_config(session)
  servers = session.available_mcp_servers

  config = {
    mcpServers: servers.each_with_object({}) do |server, hash|
      hash[server.name] = {
        url: server.url,
        transport: server.transport.to_s
      }

      # Add headers if present
      if server.headers.present?
        hash[server.name][:headers] = server.headers
      end
    end
  }

  config
end

# Inject into container as environment variable
env_vars << "MCP_CONFIG=#{build_mcp_config(session).to_json}"
```

### Task 5: Frontend — RTK Query Endpoint (AC: 1)

- [ ] Add `useGetAvailableMcpServersQuery` to API
- [ ] Define `AvailableMcpServer` type

```typescript
// Add to projectsApi.ts or create mcpServersApi.ts
getAvailableMcpServers: builder.query<AvailableMcpServer[], string>({
  query: (projectId) => `/projects/${projectId}/available_mcp_servers`,
  transformResponse: (response: { items: AvailableMcpServer[] }) => response.items,
}),

interface AvailableMcpServer {
  id: number;
  name: string;
  displayName: string;
  url: string;
  transport: 'sse' | 'stdio';
  description: string | null;
  scopeIndicator: string;
  enabled: boolean;
}
```

### Task 6: Frontend — MCP Server Selector Component (AC: 1, 2, 3)

- [ ] Create `McpServerSelector` component
- [ ] Display servers as checkboxes with name, URL, scope
- [ ] Show info about auto-included Palad server when tools selected
- [ ] Support multi-select (0..N)

```typescript
// app/frontend/features/session/ui/McpServerSelector.tsx
interface McpServerSelectorProps {
  projectId: string;
  selectedServerIds: number[];
  hasToolsSelected: boolean;  // From ToolSelector
  onChange: (serverIds: number[]) => void;
}

export const McpServerSelector: FC<McpServerSelectorProps> = ({
  projectId,
  selectedServerIds,
  hasToolsSelected,
  onChange,
}) => {
  const { data: servers, isLoading } = useGetAvailableMcpServersQuery(projectId);

  return (
    <Box>
      <Typography variant="subtitle2">MCP Servers (optional)</Typography>

      {hasToolsSelected && (
        <Alert severity="info" sx={{ mb: 1 }}>
          "Palad Tools" server will be automatically included for custom tools.
        </Alert>
      )}

      <FormGroup>
        {servers?.map((server) => (
          <FormControlLabel
            key={server.id}
            control={
              <Checkbox
                checked={selectedServerIds.includes(server.id)}
                onChange={(e) => {
                  if (e.target.checked) {
                    onChange([...selectedServerIds, server.id]);
                  } else {
                    onChange(selectedServerIds.filter(id => id !== server.id));
                  }
                }}
              />
            }
            label={
              <Box>
                <Typography>{server.displayName}</Typography>
                <Typography variant="caption" color="text.secondary">
                  {server.url}
                </Typography>
                <Chip size="small" label={server.scopeIndicator} />
              </Box>
            }
          />
        ))}
      </FormGroup>

      {servers?.length === 0 && (
        <Typography color="text.secondary">
          No MCP servers configured. Add servers in Settings → MCP Servers.
        </Typography>
      )}
    </Box>
  );
};
```

### Task 7: Frontend — Integrate with Session Start Form (AC: 3, 4)

- [ ] Add `McpServerSelector` to session start form
- [ ] Pass `hasToolsSelected` from ToolSelector state
- [ ] Include `mcpServerIds` in create session mutation

```typescript
// In session start form
const [selectedToolIds, setSelectedToolIds] = useState<number[]>([]);
const [selectedServerIds, setSelectedServerIds] = useState<number[]>([]);

const handleStartSession = async () => {
  await createSession({
    projectId,
    agentType,
    toolIds: selectedToolIds,
    mcpServerIds: selectedServerIds,
  });
};

return (
  <>
    <ToolSelector
      projectId={projectId}
      selectedToolIds={selectedToolIds}
      onChange={setSelectedToolIds}
    />

    <McpServerSelector
      projectId={projectId}
      selectedServerIds={selectedServerIds}
      hasToolsSelected={selectedToolIds.length > 0}
      onChange={setSelectedServerIds}
    />
  </>
);
```

### Task 8: Tests (AC: all)

- [ ] Model: SessionMcpServer validations, associations
- [ ] Model: TerminalSession#available_mcp_servers
- [ ] Controller: Create session with mcp_server_ids
- [ ] Service: build_mcp_config generates correct JSON
- [ ] Frontend: McpServerSelector component

## Dev Notes

### Internal Server Logic

The internal "Palad Tools" server is **not stored in database**. It's dynamically added to `available_mcp_servers` when the session has any tools selected (via 7.2).

This approach:
- Avoids database clutter
- Uses environment variable for URL
- Automatically includes session's mcp_key in headers

### MCP Config Format

The MCP config is injected as JSON environment variable. Example:

```json
{
  "mcpServers": {
    "palad-tools": {
      "url": "http://web:3000/action_mcp",
      "transport": "sse",
      "headers": {
        "X-Session-Key": "abc123..."
      }
    },
    "context7": {
      "url": "https://mcp.context7.io",
      "transport": "sse",
      "headers": {
        "Authorization": "Bearer token..."
      }
    }
  }
}
```

### Relationship with 7.2 (Tool Selection)

- 7.2 handles Tool selection → `session_tools`
- 7.5 handles MCP Server selection → `session_mcp_servers`
- Internal Palad server is auto-added if tools selected

Both selectors appear on session start form.

### FSD Structure

- Join model: `web/app/models/session_mcp_server.rb`
- API: `entities/project/api/projectsApi.ts`
- Selector: `features/session/ui/McpServerSelector.tsx`

### References

- [Source: web/app/models/terminal_session.rb] — session model
- [Source: web/app/services/container_service.rb] — container config
- [Source: _bmad-output/7-2-select-tools-for-session-ui.md] — tool selection pattern
- [Source: _bmad-output/7-4-mcp-server-management.md] — MCP server model

## Dev Agent Record

### Agent Model Used

### Debug Log References

### Completion Notes List

### File List
