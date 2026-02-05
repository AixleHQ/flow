# Core Architectural Decisions

## Decision Priority Analysis

**Critical Decisions (Block Implementation):**
- Data modeling approach (ActiveRecord primary)
- Authentication method (Google OAuth)
- API design pattern (REST)
- State management (Redux Toolkit + Zustand)
- Hosting strategy (AWS ECS Fargate)

**Important Decisions (Shape Architecture):**
- Authorization patterns (RBAC + Pundit)
- Error handling (Rails standard)
- Performance optimization (code splitting, lazy loading)
- CI/CD pipeline (GitHub Actions)
- Monitoring (Lograge + Sentry + Temporal UI)

**Deferred Decisions (Post-MVP):**
- Rate limiting (skipped for MVP)
- Scaling strategy (deferred due to Docker sessions)
- Multiple OAuth providers (expansion later)

## Data Architecture

**Database Choice:** PostgreSQL 15.3 (already in use)

**Data Modeling Approach:**
- **Primary:** ActiveRecord ORM (main approach)
- **Fallback:** Raw SQL for complex analytical queries
- **Rationale:** ActiveRecord provides simplicity and productivity for most cases, raw SQL for optimization where necessary

**Data Validation Strategy:**
- **Multi-level validation:** Database constraints + Model validations + Service-level validation
- **Database constraints:** NOT NULL, foreign keys, check constraints for data integrity
- **Model validations:** Rails validations for UX and business rules
- **Service-level:** Complex business logic in service classes
- **Rationale:** Three-tier protection ensures data integrity at all levels

**Migration Strategy:**
- **Approach:** Rails migrations
- **Rationale:** Standard Rails approach, already used in the project

**Caching Strategy:**
- **Redis:** Session state, frequent queries, real-time data
- **Rails cache:** Application-level caching
- **CDN:** Static files and assets
- **Database query caching:** Automatic via ActiveRecord
- **Rationale:** Multi-layered caching for performance optimization

## Authentication & Security

**Authentication Method:**
- **Approach:** Google OAuth only (for MVP)
- **Future:** Ability to expand to other OAuth providers
- **Rationale:** Simplicity for MVP, internal tool, Google OAuth already implemented

**Authorization Patterns:**
- **Approach:** RBAC (Role-Based Access Control) + Pundit policies everywhere
- **Roles:** Admin, Collaborator
- **Policy objects:** Pundit for flexible checks at the project/resource level
- **Rationale:** RBAC provides the basic structure, Pundit gives flexibility for complex cases

**Security Middleware:**
- **Approach:** Rails built-in security + Rack middleware
- **Components:** CSRF protection, secure headers, rate limiting middleware
- **Rationale:** Rails built-in provides baseline protection, Rack middleware for additional requirements

**Data Encryption Approach:**
- **Secrets:** ActiveSupport::MessageEncryptor
- **Rationale:** Simplicity and integration with Rails credentials

**API Security Strategy:**
- **Approach:** Session-based authentication for all APIs (including the UI API)
- **Rationale:** Simplification for MVP, all APIs are used only for the UI, no external clients

## API & Communication Patterns

**API Design Pattern:**
- **Approach:** REST API for all endpoints
- **Rationale:** Standard approach, already in use, suitable for all cases

**API Documentation Approach:**
- **Approach:** OAS Rails (OpenAPI Specification for Rails)
- **Rationale:** Automatic documentation generation from Rails controllers

**Error Handling Standards:**
- **Approach:** Rails standard errors
- **Rationale:** Simplicity and consistency with the Rails approach

**Rate Limiting Strategy:**
- **Approach:** Skipped for MVP
- **Rationale:** Internal tool, rate limiting is not critical at the initial stage

**Communication Between Services:**
- **Approach:** Temporal for orchestration
- **Rationale:** Temporal is already in use and sufficient for all inter-service communications

## Frontend Architecture

**State Management Approach:**
- **Approach:** Redux Toolkit + Zustand (hybrid)
- **Redux Toolkit:** Global state (API cache, user state)
- **Zustand:** Local component state
- **Rationale:** Optimal balance between centralized and local state

**Component Architecture:**
- **Approach:** Feature-Sliced Design
- **Rationale:** Already in use, well-structured architecture

**Routing Strategy:**
- **Approach:** TanStack Router
- **Rationale:** Type-safe routing, already in use

**Performance Optimization:**
- **Code splitting:** Vite dynamic imports
- **Lazy loading:** Components and routes
- **Memoization:** React.memo, useMemo, useCallback where necessary
- **Virtual scrolling:** For large artifact lists
- **Rationale:** Comprehensive optimization for performance

**Bundle Optimization:**
- **Approach:** Vite build optimization + chunk splitting
- **Rationale:** Optimization of bundle size and load time

## Infrastructure & Deployment

**Hosting Strategy:**
- **Approach:** AWS ECS Fargate
- **Rationale:** Serverless containers, managed service, suitable for Docker-based architecture

**CI/CD Pipeline Approach:**
- **Approach:** GitHub Actions
- **Rationale:** Integration with GitHub, automation of tests and deployment

**Environment Configuration:**
- **Development:** .env and .env.development + Docker Compose + settings.yml
- **Production:** AWS environment variables + AWS Secrets Manager
- **Rationale:** Simplicity for development, security for production

**Monitoring and Logging:**
- **Structured logging:** Lograge
- **Error tracking:** Sentry
- **Workflow monitoring:** Temporal UI
- **Rationale:** Comprehensive monitoring at all levels

**Scaling Strategy:**
- **Approach:** Deferred
- **Rationale:** Docker sessions for terminals do not scale horizontally, fixed resources for MVP

## Decision Impact Analysis

**Implementation Sequence:**
1. Data models and migrations (ActiveRecord)
2. Authentication setup (Google OAuth)
3. Authorization policies (Pundit)
4. API endpoints (REST)
5. Frontend state management (Redux Toolkit + Zustand)
6. Performance optimizations (code splitting, lazy loading)
7. CI/CD pipeline (GitHub Actions)
8. Deployment setup (AWS ECS Fargate)

**Cross-Component Dependencies:**
- Authentication → Authorization → API endpoints
- Data models → API endpoints → Frontend state
- Frontend architecture → Performance optimizations
- Infrastructure → CI/CD → Deployment
