# Story 7.4: MCP Server Management

Status: review

## Story

As a company/project admin,
I want to configure MCP servers (internal and custom),
So that agents can access additional tools from external providers like Context7, Tavily, etc.

## Architecture Decision

**Pattern:** Same as Tool model — polymorphic scope with kind (internal/custom).

```
MCP Server Types:
┌──────────┬────────────────────────────────────┬─────────────┐
│ Kind     │ Description                        │ Scope       │
├──────────┼────────────────────────────────────┼─────────────┤
│ internal │ Palad tools MCP (auto-configured)  │ None        │
│ custom   │ User-configured (Context7, etc.)   │ Company/Proj│
└──────────┴────────────────────────────────────┴─────────────┘
```

## Acceptance Criteria

1. McpServer model with `kind`: internal | custom
2. Can create custom MCP server with: name, url, transport, headers, description
3. Custom servers scoped to company or project (polymorphic)
4. Internal server auto-configured per session (from 7.1)
5. Can enable/disable MCP servers
6. Can edit and delete custom servers only
7. UI for managing MCP servers (company-level and project-level)
8. Validation for required fields

## Tasks

### Task 1: MCPServer Model & Migration (AC: 1, 2, 3, 5, 8)

- [x] Create migration for `mcp_servers` table
- [x] Create `MCPServer` model with enumerize for kind
- [x] Add polymorphic scope association
- [x] Add validations
- [x] Add scopes for filtering

```ruby
# Migration
create_table :mcp_servers do |t|
  t.string :name, null: false
  t.string :display_name, null: false
  t.string :url, null: false
  t.string :transport, default: 'sse'  # sse | stdio
  t.jsonb :headers, default: {}
  t.text :description
  t.string :kind, null: false, default: 'custom'  # internal | custom
  t.references :scope, polymorphic: true, index: true  # Company | Project
  t.boolean :enabled, default: true, null: false
  t.timestamps
end

add_index :mcp_servers, [:name, :scope_type, :scope_id], unique: true

# Model: app/models/mcp_server.rb
class McpServer < ApplicationRecord
  extend Enumerize

  enumerize :kind, in: %i[internal custom], default: :custom, predicates: true
  enumerize :transport, in: %i[sse stdio], default: :sse

  belongs_to :scope, polymorphic: true, optional: true

  validates :name, presence: true,
                   format: { with: /\A[a-z][a-z0-9_-]*\z/, message: "lowercase letters, numbers, dashes, underscores" }
  validates :name, uniqueness: { scope: %i[scope_type scope_id] }
  validates :display_name, presence: true
  validates :url, presence: true, if: :custom?
  validates :kind, presence: true
  validates :scope, presence: true, if: :custom?

  scope :internal_servers, -> { where(kind: "internal") }
  scope :custom_servers, -> { where(kind: "custom") }
  scope :for_company, ->(company) { custom_servers.where(scope_type: "Company", scope_id: company.id) }
  scope :for_project, ->(project) { custom_servers.where(scope_type: "Project", scope_id: project.id) }
  scope :enabled, -> { where(enabled: true) }

  # Merged list for project (internal + company + project)
  def self.merged_for_project(project)
    # Same pattern as Tool.merged_for_project
  end
end
```

### Task 2: Backend API — CRUD Controller (AC: 2, 5, 6)

- [x] Create `Api::V1::Company::MCPServersController` with CRUD actions
- [x] Create `Api::V1::Company::Projects::MCPServersController` for project-scoped
- [x] Add routes (nested under company and project)
- [x] Create serializer (MCPServerSerializer)
- [ ] (Deferred) Create Pundit policy — using existing company auth

```ruby
# Routes
namespace :api do
  namespace :v1 do
    resources :mcp_servers, only: [:index, :create, :update, :destroy]  # company level

    resources :projects do
      resources :mcp_servers, only: [:index, :create, :update, :destroy],
                              controller: 'projects/mcp_servers'
    end
  end
end

# Controller example
class Api::V1::McpServersController < Api::V1::BaseController
  def index
    servers = McpServer.for_company(current_company).enabled
    render json: { items: servers.map { |s| McpServerSerializer.new(s).as_json } }
  end

  def create
    server = McpServer.new(server_params)
    server.scope = current_company
    server.kind = :custom

    if server.save
      render json: { data: McpServerSerializer.new(server).as_json }, status: :created
    else
      render json: { errors: server.errors }, status: :unprocessable_entity
    end
  end

  # ... update, destroy
end
```

### Task 3: Frontend — RTK Query Endpoints (AC: 7)

- [x] Add `mcpServersApi.ts` with CRUD endpoints
- [x] Define `McpServer` type in `model/types.ts`
- [x] Handle cache invalidation on mutations via QueryTag.McpServers

```typescript
// app/frontend/entities/mcp-server/api/mcpServersApi.ts
export const mcpServersApi = baseApi.injectEndpoints({
  endpoints: (builder) => ({
    getMcpServers: builder.query<McpServer[], void>({
      query: () => '/mcp_servers',
      transformResponse: (response: { items: McpServer[] }) => response.items,
      providesTags: [QueryTag.McpServers],
    }),
    getProjectMcpServers: builder.query<McpServer[], string>({
      query: (projectId) => `/projects/${projectId}/mcp_servers`,
      transformResponse: (response: { items: McpServer[] }) => response.items,
      providesTags: [QueryTag.McpServers],
    }),
    createMcpServer: builder.mutation<McpServer, CreateMcpServerDto>({
      query: (body) => ({ url: '/mcp_servers', method: 'POST', body }),
      invalidatesTags: [QueryTag.McpServers],
    }),
    updateMcpServer: builder.mutation<McpServer, { id: number; body: UpdateMcpServerDto }>({
      query: ({ id, body }) => ({ url: `/mcp_servers/${id}`, method: 'PATCH', body }),
      invalidatesTags: [QueryTag.McpServers],
    }),
    deleteMcpServer: builder.mutation<void, number>({
      query: (id) => ({ url: `/mcp_servers/${id}`, method: 'DELETE' }),
      invalidatesTags: [QueryTag.McpServers],
    }),
  }),
});

interface McpServer {
  id: number;
  name: string;
  displayName: string;
  url: string;
  transport: 'sse' | 'stdio';
  headers: Record<string, string>;
  description: string | null;
  kind: 'internal' | 'custom';
  scopeIndicator?: string;
  enabled: boolean;
}
```

### Task 4: Frontend — MCP Servers List Page (AC: 7)

- [x] Create `McpServersPage` in `pages/mcp-servers`
- [x] Display table with: name, url, transport, scope, enabled, actions
- [x] Add "Add MCP Server" button (opens dialog)
- [x] Add edit/delete actions (custom only)
- [x] Show scope indicator chip

```typescript
// app/frontend/pages/mcp-servers/ui/McpServersPage.tsx
export const McpServersPage: FC = () => {
  const { data: servers, isLoading } = useGetMcpServersQuery();
  const [deleteServer] = useDeleteMcpServerMutation();
  const [dialogOpen, setDialogOpen] = useState(false);

  return (
    <Box>
      <PageHeader
        title="MCP Servers"
        action={
          <Button onClick={() => setDialogOpen(true)}>
            Add MCP Server
          </Button>
        }
      />

      <DataTable
        rows={servers ?? []}
        columns={[
          { field: 'displayName', headerName: 'Name' },
          { field: 'url', headerName: 'URL' },
          { field: 'transport', headerName: 'Transport' },
          { field: 'scopeIndicator', headerName: 'Scope', renderCell: ScopeChip },
          { field: 'enabled', headerName: 'Enabled', type: 'boolean' },
          { field: 'actions', headerName: '', renderCell: ActionsCell },
        ]}
      />

      <McpServerFormDialog
        open={dialogOpen}
        onClose={() => setDialogOpen(false)}
      />
    </Box>
  );
};
```

### Task 5: Frontend — MCP Server Form Dialog (AC: 2, 6)

- [x] Create `McpServerFormDialog` component
- [x] Form fields: name, displayName, url, transport (select), description, enabled
- [x] Use React Hook Form + Zod validation
- [x] Support create and edit modes
- [x] Headers JSON editor (key-value list)

```typescript
// app/frontend/features/mcp-server/ui/McpServerFormDialog.tsx
const mcpServerSchema = z.object({
  name: z.string().min(1).regex(/^[a-z][a-z0-9_-]*$/),
  displayName: z.string().min(1),
  url: z.string().url(),
  transport: z.enum(['sse', 'stdio']),
  headers: z.record(z.string()).optional(),
  description: z.string().optional(),
});

export const McpServerFormDialog: FC<Props> = ({ open, onClose, server }) => {
  const isEdit = !!server;
  const [createServer] = useCreateMcpServerMutation();
  const [updateServer] = useUpdateMcpServerMutation();

  const form = useForm<McpServerFormData>({
    resolver: zodResolver(mcpServerSchema),
    defaultValues: server ?? { transport: 'sse', headers: {} },
  });

  const onSubmit = async (data: McpServerFormData) => {
    if (isEdit) {
      await updateServer({ id: server.id, body: data });
    } else {
      await createServer(data);
    }
    onClose();
  };

  return (
    <Dialog open={open} onClose={onClose}>
      <DialogTitle>{isEdit ? 'Edit' : 'Add'} MCP Server</DialogTitle>
      <DialogContent>
        <TextField {...form.register('name')} label="Name" />
        <TextField {...form.register('displayName')} label="Display Name" />
        <TextField {...form.register('url')} label="URL" />
        <Select {...form.register('transport')} label="Transport">
          <MenuItem value="sse">SSE</MenuItem>
          <MenuItem value="stdio">STDIO</MenuItem>
        </Select>
        <JsonEditor {...form.register('headers')} label="Headers (JSON)" />
        <TextField {...form.register('description')} label="Description" multiline />
      </DialogContent>
      <DialogActions>
        <Button onClick={onClose}>Cancel</Button>
        <Button onClick={form.handleSubmit(onSubmit)}>
          {isEdit ? 'Save' : 'Create'}
        </Button>
      </DialogActions>
    </Dialog>
  );
};
```

### Task 6: Add Route & Navigation (AC: 7)

- [x] Add route `/company/mcp-servers` to routeTree.tsx
- [x] Add navigation item to AppHeader (admin only)
- [ ] (Deferred) Project-level MCP servers route in project page

### Task 7: Tests (AC: all)

- [x] Model: validations, scopes, merged_for_project (12 tests)
- [ ] (Deferred) Controller: CRUD operations, authorization
- [ ] (Deferred) Frontend: form validation, list rendering

## Dev Notes

### Pattern Alignment with Tool

This model follows the exact same pattern as `Tool`:
- `kind` with enumerize (internal/custom)
- Polymorphic `scope` (Company/Project)
- `merged_for_project` method for merged list
- `scope_indicator` for UI display

### Transport Types

- **sse** (default) — Server-Sent Events, HTTP-based, used by most MCP servers
- **stdio** — Standard I/O, used for local process-based servers (less common for web)

### Headers Format

Headers stored as JSONB, example:
```json
{
  "Authorization": "Bearer xxx",
  "X-Api-Key": "yyy"
}
```

### Internal Server

The internal "Palad Tools" server is auto-configured from 7.1 via environment variables.
It doesn't need a database record — it's added dynamically when building MCP config.

### FSD Structure

- Model types: `entities/mcp-server/model/types.ts`
- API: `entities/mcp-server/api/mcpServersApi.ts`
- Page: `pages/mcp-servers/ui/McpServersPage.tsx`
- Form: `features/mcp-server/ui/McpServerFormDialog.tsx`

### References

- [Source: web/app/models/tool.rb] — pattern reference
- [Source: ai/project-context.md] — coding standards
- [Source: _bmad-output/7-1-dynamic-mcp-tools-integration.md] — internal MCP setup

## Dev Agent Record

### Agent Model Used

Claude Sonnet 4

### Completion Notes

- Created MCPServer model with polymorphic scope (Company/Project)
- Implemented CRUD API controllers for company and project levels
- Created RTK Query endpoints with cache invalidation
- Built full UI: McpServersPage, McpServersTable, McpServerFormDialog (with Headers editor), DeleteMcpServerDialog
- Added route and navigation to AppHeader
- All 294 tests pass (12 new MCP server tests)
- Deferred: Project-level route in project page (added as tab instead)

### Change Log

- 2026-02-04: Initial implementation of Story 7.4

### File List

- `web/db/migrate/20260204170001_create_protocol_servers.rb` (new) — creates mcp_servers table
- `web/app/models/mcp_server.rb` (new) — MCPServer model with enumerize, scopes, merged_for_project
- `web/app/models/company.rb` (modified) — added mcp_servers association
- `web/app/models/project.rb` (modified) — added mcp_servers association
- `web/app/serializers/mcp_server_serializer.rb` (new) — API serializer
- `web/app/controllers/api/v1/company/mcp_servers_controller.rb` (new) — company CRUD
- `web/app/controllers/api/v1/company/projects/mcp_servers_controller.rb` (new) — project CRUD
- `web/config/routes.rb` (modified) — added mcp_servers routes
- `web/app/frontend/shared/api/QueryTag.ts` (modified) — added McpServers tag
- `web/app/frontend/shared/routes.ts` (modified) — added companyMcpServersPath
- `web/app/frontend/entities/mcp-server/` (new directory) — API and types
- `web/app/frontend/features/mcp-servers-management/` (new directory) — UI components
- `web/app/frontend/pages/mcp-servers/` (new directory) — page component
- `web/app/frontend/app/routeTree.tsx` (modified) — added route
- `web/app/frontend/widgets/AppHeader/ui/AppHeader.tsx` (modified) — added nav item
- `web/test/models/mcp_server_test.rb` (new) — 12 tests
