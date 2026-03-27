# Story 4.5: Config Items UI

Status: review

## Story

As a user,
I want a unified UI to view and manage all config items,
So that I can easily understand my environment configuration.

## Acceptance Criteria

1. **AC1:** Single table showing all config items (merged company + project for project context)
2. **AC2:** Columns: Name, Type (Secret/Variable), Value, Scope, Description, Actions
3. **AC3:** Value column: Variables show actual value, Secrets show ••••••••
4. **AC4:** Type column: badge/chip (Secret = red, Variable = blue)
5. **AC5:** Scope column: shows "(company)" or "(project)" or "(overrides company)"
6. **AC6:** Filter by: Type (Secret/Variable/All)
7. **AC7:** Search by name
8. **AC8:** Delete with confirmation dialog
9. **AC9:** Create button opens modal/drawer with type toggle

## Tasks / Subtasks

- [x] Task 1: Create ConfigItemsPage component (AC: 1, 2)
  - [x] 1.1: Create page component with table layout
  - [x] 1.2: Add to routing (company settings and project settings)
  - [x] 1.3: Fetch data from API using RTK Query

- [x] Task 2: Implement table columns (AC: 2, 3, 4, 5)
  - [x] 2.1: Name column
  - [x] 2.2: Type column with colored badge (Secret=red, Variable=blue)
  - [x] 2.3: Value column (masked for secrets)
  - [x] 2.4: Scope column with indicator badge
  - [x] 2.5: Description column
  - [x] 2.6: Actions column (edit, delete)

- [x] Task 3: Implement filters and search (AC: 6, 7)
  - [x] 3.1: Type filter dropdown (All/Secret/Variable)
  - [x] 3.2: Search input for name

- [x] Task 4: Create/Edit modal (AC: 9)
  - [x] 4.1: Create ConfigItemFormModal component
  - [x] 4.2: Form fields: name, value, description, type toggle
  - [x] 4.3: Handle create and update API calls
  - [x] 4.4: Value field behavior: show for variable, password input for secret

- [x] Task 5: Delete confirmation (AC: 8)
  - [x] 5.1: Delete confirmation dialog
  - [x] 5.2: Handle delete API call

## Dev Notes

### Frontend Architecture (Feature-Sliced Design)

```
web/app/frontend/
├── entities/
│   └── config-item/
│       ├── model/
│       │   ├── types.ts
│       │   └── api.ts (RTK Query endpoints)
│       └── ui/
│           ├── ConfigItemTypeBadge.tsx
│           └── ConfigItemScopeBadge.tsx
├── features/
│   └── config-item/
│       ├── create-config-item/
│       │   └── ui/ConfigItemFormModal.tsx
│       ├── delete-config-item/
│       │   └── ui/DeleteConfigItemDialog.tsx
│       └── config-items-filters/
│           └── ui/ConfigItemsFilters.tsx
└── pages/
    └── config-items/
        └── ui/ConfigItemsPage.tsx
```

### API Integration (RTK Query)

```typescript
// entities/config-item/model/api.ts
import { baseApi } from '@/shared/api/baseApi';

export const configItemApi = baseApi.injectEndpoints({
  endpoints: (builder) => ({
    // Company-level config items
    getCompanyConfigItems: builder.query<ConfigItem[], void>({
      query: () => '/company/config_items',
      providesTags: ['ConfigItems'],
    }),

    // Project-level config items (merged list)
    getProjectConfigItems: builder.query<ConfigItem[], number>({
      query: (projectId) => `/company/projects/${projectId}/config_items`,
      providesTags: ['ConfigItems'],
    }),

    createConfigItem: builder.mutation<ConfigItem, CreateConfigItemParams>({
      query: ({ projectId, ...body }) => ({
        url: projectId
          ? `/company/projects/${projectId}/config_items`
          : '/company/config_items',
        method: 'POST',
        body: { config_item: body },
      }),
      invalidatesTags: ['ConfigItems'],
    }),

    updateConfigItem: builder.mutation<ConfigItem, UpdateConfigItemParams>({
      query: ({ id, projectId, ...body }) => ({
        url: projectId
          ? `/company/projects/${projectId}/config_items/${id}`
          : `/company/config_items/${id}`,
        method: 'PATCH',
        body: { config_item: body },
      }),
      invalidatesTags: ['ConfigItems'],
    }),

    deleteConfigItem: builder.mutation<void, DeleteConfigItemParams>({
      query: ({ id, projectId }) => ({
        url: projectId
          ? `/company/projects/${projectId}/config_items/${id}`
          : `/company/config_items/${id}`,
        method: 'DELETE',
      }),
      invalidatesTags: ['ConfigItems'],
    }),
  }),
});
```

### Types

```typescript
// entities/config-item/model/types.ts
export interface ConfigItem {
  id: number;
  name: string;
  value: string;  // Masked "••••••••" for secrets
  description: string | null;
  itemType: 'secret' | 'variable';
  scopeType: 'Company' | 'Project';
  scopeId: number;
  scopeIndicator: 'company' | 'project' | 'overrides_company';
  valueEditable: boolean;
  createdAt: string;
  updatedAt: string;
}

export interface CreateConfigItemParams {
  projectId?: number;
  name: string;
  value: string;
  description?: string;
  itemType: 'secret' | 'variable';
}

export interface UpdateConfigItemParams {
  id: number;
  projectId?: number;
  name?: string;
  value?: string;
  description?: string;
}

export interface DeleteConfigItemParams {
  id: number;
  projectId?: number;
}
```

### UI Components (Material UI)

**Type Badge:**
```tsx
// entities/config-item/ui/ConfigItemTypeBadge.tsx
<Chip
  label={itemType === 'secret' ? 'Secret' : 'Variable'}
  color={itemType === 'secret' ? 'error' : 'info'}
  size="small"
/>
```

**Scope Badge:**
```tsx
// entities/config-item/ui/ConfigItemScopeBadge.tsx
const scopeLabels = {
  company: 'Company',
  project: 'Project',
  overrides_company: 'Overrides Company',
};
<Chip
  label={scopeLabels[scopeIndicator]}
  variant={scopeIndicator === 'overrides_company' ? 'filled' : 'outlined'}
  size="small"
/>
```

### Routing

```typescript
// Add to router config
{
  path: '/settings/config-items',
  element: <ConfigItemsPage />,
}
{
  path: '/projects/:projectId/settings/config-items',
  element: <ConfigItemsPage />,
}
```

### Project Structure Notes

- Page: `web/app/frontend/pages/config-items/ui/ConfigItemsPage.tsx`
- Entity: `web/app/frontend/entities/config-item/`
- Features: `web/app/frontend/features/config-item/`
- API: RTK Query endpoints in entity model

### References

- [Source: ai/epics.md#Story 4.5]
- [Source: ai/architecture.md#Frontend] — Material UI, Redux Toolkit, Feature-Sliced Design
- [Source: web/app/serializers/config_item_serializer.rb] — API response format

## Dev Agent Record

### Agent Model Used

Claude Opus 4.5

### Debug Log References

N/A

### Completion Notes List

- Implemented ConfigItemsPage with full CRUD support for company and project levels
- Created RTK Query API endpoints for config items (get, create, update, delete)
- Implemented ConfigItemTypeBadge (red=secret, blue=variable) and ConfigItemScopeBadge (company/project/overrides_company)
- Added ConfigItemsTable with conditional actions based on context (company vs project)
- Implemented ConfigItemsFilters with type dropdown and name search (debounced)
- Created ConfigItemFormDialog with type toggle, value visibility toggle for secrets, and validation via zod schema
- Created DeleteConfigItemDialog with confirmation
- Added company-level route `/company/config-items` to routeTree
- Added Config tab to ProjectPage for project-level config items
- Added "Config" nav item to AppHeader (admin only)
- All acceptance criteria satisfied

### File List

- web/app/frontend/pages/config-items/index.ts (new)
- web/app/frontend/pages/config-items/lib/types.ts (new)
- web/app/frontend/pages/config-items/lib/configItemSchema.ts (new)
- web/app/frontend/pages/config-items/api/configItemsApi.ts (new)
- web/app/frontend/pages/config-items/ui/ConfigItemsPage.tsx (new)
- web/app/frontend/pages/config-items/ui/ConfigItemsTable.tsx (new)
- web/app/frontend/pages/config-items/ui/ConfigItemTypeBadge.tsx (new)
- web/app/frontend/pages/config-items/ui/ConfigItemScopeBadge.tsx (new)
- web/app/frontend/pages/config-items/ui/ConfigItemsFilters.tsx (new)
- web/app/frontend/pages/config-items/ui/ConfigItemFormDialog.tsx (new)
- web/app/frontend/pages/config-items/ui/DeleteConfigItemDialog.tsx (new)
- web/app/frontend/shared/api/QueryTag.ts (modified - added ConfigItems tag)
- web/app/frontend/shared/routes.ts (modified - added companyConfigItemsPath)
- web/app/frontend/app/routeTree.tsx (modified - added companyConfigItemsRoute)
- web/app/frontend/pages/project/lib/types.ts (modified - added 'config' to ProjectTab)
- web/app/frontend/pages/project/ui/ProjectPage.tsx (modified - added Config tab)
- web/app/frontend/widgets/AppHeader/ui/AppHeader.tsx (modified - added Config nav item)
