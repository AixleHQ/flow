# Story 7.2: Select Tools for Session (UI)

Status: ready-for-dev

## Story

As a user,
I want to select which custom tools are available when starting a standalone session,
So that I control what capabilities the agent has.

## Acceptance Criteria

1. Session start form shows available custom tools (company + project merged)
2. Can select 0..N tools for the session
3. Selected tools saved to `session_tools` join table
4. Default: no tools selected (explicit opt-in)
5. Tool selection UI shows tool name, description, and scope indicator

## Tasks

### Task 1: Backend — Tools API for Session Start (AC: 1)

- [ ] Create `GET /api/v1/projects/:project_id/available_tools` endpoint
- [ ] Return merged list of tools (company + project) using `Tool.merged_for_project`
- [ ] Serialize with: id, name, display_name, description, scope_indicator, enabled
- [ ] Add Pundit policy for authorization

```ruby
# app/controllers/api/v1/projects/available_tools_controller.rb
class Api::V1::Projects::AvailableToolsController < Api::V1::BaseController
  def index
    tools = Tool.merged_for_project(project).select(&:custom?)
    render json: { items: tools.map { |t| serialize_tool(t) } }
  end

  private

  def serialize_tool(tool)
    {
      id: tool.id,
      name: tool.name,
      displayName: tool.display_name,
      description: tool.description,
      scopeIndicator: tool.scope_indicator,
      enabled: tool.enabled
    }
  end
end
```

### Task 2: Backend — Accept tool_ids on Session Create (AC: 2, 3)

- [ ] Update `TerminalSessionsController#create` to accept `tool_ids` param
- [ ] Create `session_tools` records for selected tools
- [ ] Validate that all tool_ids are valid for the project
- [ ] Update serializer to include selected tools

```ruby
# In terminal_sessions_controller.rb
def create
  @session = TerminalSession.new(session_params)
  @session.user = current_user

  if @session.save
    # Create session_tools if tool_ids provided
    create_session_tools(params[:tool_ids]) if params[:tool_ids].present?
    render json: { data: serialize_session(@session) }, status: :created
  else
    render json: { errors: @session.errors }, status: :unprocessable_entity
  end
end

private

def create_session_tools(tool_ids)
  available_tool_ids = Tool.merged_for_project(@session.project).pluck(:id)
  valid_ids = tool_ids.map(&:to_i) & available_tool_ids

  valid_ids.each do |tool_id|
    @session.session_tools.create!(tool_id: tool_id)
  end
end
```

### Task 3: Frontend — RTK Query Endpoint (AC: 1)

- [ ] Add `useGetAvailableToolsQuery` to `projectsApi.ts`
- [ ] Define `AvailableTool` type with all fields
- [ ] Handle loading and error states

```typescript
// app/frontend/entities/project/api/projectsApi.ts
export const projectsApi = baseApi.injectEndpoints({
  endpoints: (builder) => ({
    // ... existing endpoints
    getAvailableTools: builder.query<AvailableTool[], string>({
      query: (projectId) => `/projects/${projectId}/available_tools`,
      transformResponse: (response: { items: AvailableTool[] }) => response.items,
    }),
  }),
});

interface AvailableTool {
  id: number;
  name: string;
  displayName: string;
  description: string | null;
  scopeIndicator: 'internal' | 'company' | 'project' | 'overrides_company';
  enabled: boolean;
}
```

### Task 4: Frontend — Tool Selection Component (AC: 1, 2, 4, 5)

- [ ] Create `ToolSelector` component in `features/session`
- [ ] Display tools as checkboxes with name, description, scope chip
- [ ] Support multi-select (0..N)
- [ ] Default all unchecked
- [ ] Group by scope (company tools, project tools)

```typescript
// app/frontend/features/session/ui/ToolSelector.tsx
interface ToolSelectorProps {
  projectId: string;
  selectedToolIds: number[];
  onChange: (toolIds: number[]) => void;
}

export const ToolSelector: FC<ToolSelectorProps> = ({
  projectId,
  selectedToolIds,
  onChange
}) => {
  const { data: tools, isLoading } = useGetAvailableToolsQuery(projectId);

  // Filter to only custom tools (not internal)
  const customTools = tools?.filter(t => t.scopeIndicator !== 'internal') ?? [];

  return (
    <Box>
      <Typography variant="subtitle2">Custom Tools (optional)</Typography>
      <FormGroup>
        {customTools.map((tool) => (
          <FormControlLabel
            key={tool.id}
            control={
              <Checkbox
                checked={selectedToolIds.includes(tool.id)}
                onChange={(e) => {
                  if (e.target.checked) {
                    onChange([...selectedToolIds, tool.id]);
                  } else {
                    onChange(selectedToolIds.filter(id => id !== tool.id));
                  }
                }}
              />
            }
            label={
              <Box>
                <Typography>{tool.displayName}</Typography>
                <Typography variant="caption" color="text.secondary">
                  {tool.description}
                </Typography>
                <Chip size="small" label={tool.scopeIndicator} />
              </Box>
            }
          />
        ))}
      </FormGroup>
    </Box>
  );
};
```

### Task 5: Frontend — Integrate with Session Start Form (AC: 2, 3)

- [ ] Add `ToolSelector` to session start form/dialog
- [ ] Pass selected `toolIds` to create session mutation
- [ ] Show selected tools count in form summary

### Task 6: Tests (AC: all)

- [ ] Backend: Test available_tools endpoint returns merged tools
- [ ] Backend: Test session creation with tool_ids
- [ ] Backend: Test validation rejects invalid tool_ids
- [ ] Frontend: Test ToolSelector component renders tools
- [ ] Frontend: Test checkbox selection state

## Dev Notes

### Existing Infrastructure (from 7.1)

- `session_tools` join table already exists
- `TerminalSession#tools` association already exists
- `TerminalSession#available_tools` method exists

### Scoping Pattern (from Tool model)

Tools use polymorphic scope pattern:
- `kind: internal` — system tools, no scope
- `kind: custom` — user tools with Company or Project scope

Use `Tool.merged_for_project(project)` to get merged list with `scope_indicator`.

### FSD Structure

- API endpoint: `entities/project/api/projectsApi.ts`
- Component: `features/session/ui/ToolSelector.tsx`
- Types: `entities/project/model/types.ts`

### References

- [Source: web/app/models/tool.rb#merged_for_project]
- [Source: web/app/models/terminal_session.rb#available_tools]
- [Source: _bmad-output/7-1-dynamic-mcp-tools-integration.md]

## Dev Agent Record

### Agent Model Used

### Debug Log References

### Completion Notes List

### File List
