# Technical document: WordPress Staging Site — Dualboot Partners

> Created: 2026-03-09
> Data source: live requests to the WordPress MCP API of the staging site
> Staging URL: `https://testmcpdbp.wpenginepowered.com`

---

## Contents

1. [Overview](#1-overview)
2. [Infrastructure and environment](#2-infrastructure-and-environment)
3. [MCP integration architecture](#3-mcp-integration-architecture)
4. [MCP server: configuration in Cursor](#4-mcp-server-configuration-in-cursor)
5. [Full MCP Abilities reference](#5-full-mcp-abilities-reference)
6. [SDLC Workflow for WordPress](#6-sdlc-workflow-for-wordpress)
7. [Content structure](#7-content-structure)
8. [Navigation and menus](#8-navigation-and-menus)
9. [Full page catalog](#9-full-page-catalog)
10. [Blog (Insights)](#10-blog-insights)
11. [Media library](#11-media-library)
12. [Taxonomies](#12-taxonomies)
13. [Users and roles](#13-users-and-roles)
14. [URL routing](#14-url-routing)
15. [Known limitations and quirks](#15-known-limitations-and-quirks)
16. [Diagrams](#16-diagrams)

---

## 1. Overview

The Dualboot Partners staging site is a copy of the company's corporate website, hosted on WP Engine for testing content, integrations, and automations before deploying to production.

Primary purpose:
- Testing new content (posts, pages) before publishing on the main site
- Integration with AI agents via the MCP protocol to automate content management
- Prototyping new pages and functionality

The site is a B2B corporate website for an IT company with sections: services, industries, technologies, blog (Insights), case studies, and about pages.

---

## 2. Infrastructure and environment

| Parameter | Value |
|----------|----------|
| **Hosting** | WP Engine (managed WordPress hosting) |
| **URL** | `https://testmcpdbp.wpenginepowered.com` |
| **WordPress** | 6.9.1 |
| **PHP** | 8.4.17 |
| **Database** | MySQL 8.4.7-7 |
| **Environment** | production (WP Engine staging environment label) |
| **Encoding** | UTF-8 |
| **Language** | en-US |
| **Admin email** | anton.dmitriev@dualbootpartners.com |
| **Site Name** | Dualboot Partners |
| **Site Description** | Dualboot Partners |

### Plugin stack (relevant to MCP and SDLC)

| Plugin | Version | Purpose |
|--------|--------|-----------|
| **MCP Adapter** | — | Bridge between the WordPress Abilities API and the MCP protocol. HTTP endpoint compatible with MCP 2025-06-18 (streamable HTTP) |
| **Palad WP Abilities** | 2.2.0 | Custom plugin: 35 abilities (content, media, taxonomies, users, Elementor, ACF, redirects, public previews, self-update) + MCP exposure of 3 core abilities |
| **Elementor / Elementor Pro** | — | Page builder, used for most pages. Data is stored in `_elementor_data` post meta |
| **Advanced Custom Fields (ACF) Pro** | — | Custom fields, Custom Post Types (Case Studies, etc.) |
| **Redirection** | — | URL redirect management |
| **Public Post Preview** | 2.10.0 | Generates secret links to drafts for QA without authentication |

---

## 3. MCP integration architecture

### What MCP means in the context of this site

MCP (Model Context Protocol) is a protocol that lets AI agents interact with external systems through a standardized interface. In this case the WordPress site acts as the MCP server, and the Cursor IDE as the MCP client.

### Interaction chain

```
Cursor IDE (MCP Client)
    │
    ▼ MCP Protocol (streamable HTTP)
    │
WP Engine Server
    │
    ▼ REST API
    │
MCP Adapter Plugin
    │
    ▼ WordPress Abilities API
    │
Palad WP Abilities Plugin
    │
    ▼ WordPress Core APIs (WP_Query, wp_insert_post, etc.)
    │
MySQL 8.4
```

### MCP Endpoint

```
URL:      https://testmcpdbp.wpenginepowered.com/wp-json/mcp/mcp-adapter-default-server
Auth:     Application Password (HTTP Basic Auth)
Protocol: MCP 2025-06-18 (streamable HTTP)
```

### Authentication

WordPress Application Passwords (the built-in mechanism in WP 5.6+) are used. Credentials are passed via HTTP Basic Auth in every request to the MCP endpoint.

---

## 4. MCP server: configuration in Cursor

### Server identification

| Property | Value |
|----------|----------|
| Server Identifier | `project-0-app-wordpress-staging` |
| Server Name | `wordpress-staging` |
| Folder | `mcps/project-0-app-wordpress-staging/` |

### Available MCP Tools (meta level)

The server provides 3 meta-tools through which all interaction takes place:

#### 1. `mcp-adapter-discover-abilities`
Retrieving the list of all registered WordPress abilities.
- **Parameters:** none
- **Returns:** array of `{ name, label, description }`

#### 2. `mcp-adapter-get-ability-info`
Retrieving detailed information about a specific ability, including input/output schema.
- **Parameters:** `ability_name` (string, required)
- **Returns:** `{ name, label, description, input_schema, output_schema, meta }`

#### 3. `mcp-adapter-execute-ability`
Executing an ability with parameters.
- **Parameters:** `ability_name` (string, required), `parameters` (object, required)
- **Returns:** `{ success, data?, error? }`

---

## 5. Complete MCP Abilities Reference

> **Total: 38 abilities** — 3 core + 35 palad (v2.2.0)

### 5.1 Core Abilities (3)

| Ability | Description | Input | Output |
|---------|----------|-------|--------|
| `core/get-site-info` | Site information | `fields?` (array of enum: name, description, url, wpurl, admin_email, charset, language, version) | `{ name, description, url, wpurl, admin_email, charset, language, version }` |
| `core/get-user-info` | Current authenticated user | — | `{ id, display_name, user_nicename, user_login, roles[], locale }` |
| `core/get-environment-info` | Runtime diagnostics | — | `{ environment, php_version, db_server_info, wp_version }` |

---

### 5.2 Content — CRUD (7)

#### `palad/list-posts`
| Parameter | Type | Default | Description |
|----------|-----|---------|----------|
| `post_type` | string | `"post"` | `post`, `page`, `case-study` or custom |
| `status` | string | `"publish"` | Post status |
| `per_page` | integer | 20 | Posts per page |
| `page` | integer | 1 | Page number |
| `search` | string | — | Text search |
| `category` | string | — | Category slug |
| `tag` | string | — | Tag slug |
| `orderby` | string | `"date"` | Sort field |
| `order` | string | `"DESC"` | Direction |

**Output:** `{ posts: [{ id, title, status, type, date, slug, url, author }], total, pages }`

#### `palad/get-post`
**Input:** `post_id` (integer, **required**)
**Output:** Full post object (content, meta, categories, tags)

#### `palad/create-post`
| Parameter | Type | Default | Required |
|----------|-----|---------|----------|
| `post_type` | string | `"post"` | |
| `title` | string | — | ✅ |
| `content` | string | — | ✅ |
| `excerpt` | string | — | |
| `status` | string | `"draft"` | |
| `slug` | string | — | |
| `parent_id` | integer | — | |
| `categories` | array[string] | — | |
| `tags` | array[string] | — | |
| `featured_image_id` | integer | — | |

#### `palad/update-post`
| Parameter | Type | Required |
|----------|-----|----------|
| `post_id` | integer | ✅ |
| `title`, `content`, `excerpt`, `status`, `slug` | string | |
| `categories`, `tags` | array[string] | |
| `featured_image_id` | integer | |

#### `palad/delete-post`
| Parameter | Type | Default | Required |
|----------|-----|---------|----------|
| `post_id` | integer | — | ✅ |
| `force` | boolean | `false` | |

#### `palad/search`
| Parameter | Type | Default | Required |
|----------|-----|---------|----------|
| `query` | string | — | ✅ |
| `post_types` | array[string] | `["post","page"]` | |
| `per_page` | integer | 10 | |

#### `palad/get-post-meta` / `palad/update-post-meta`
Reading and writing arbitrary meta fields (including ACF).

| Ability | Parameters |
|---------|-----------|
| `get-post-meta` | `post_id` (required) → returns all meta fields, including ACF |
| `update-post-meta` | `post_id` (required), `meta` (object: key→value) |

---

### 5.3 Media (2)

#### `palad/list-media`
| Parameter | Type | Default |
|----------|-----|---------|
| `per_page` | integer | 20 |
| `page` | integer | 1 |
| `search` | string | — |
| `mime_type` | string | — |

#### `palad/upload-media`
| Parameter | Type | Required |
|----------|-----|----------|
| `filename` | string | ✅ |
| `base64` | string | one of the two |
| `source_url` | string | one of the two |
| `title`, `alt` | string | |

---

### 5.4 Taxonomies — CRUD (4)

| Ability | Description | Key parameters |
|---------|----------|-------------------|
| `palad/list-terms` | List of terms | `taxonomy` (default: `category`), `per_page`, `search`, `hide_empty` |
| `palad/create-term` | Create a term | `taxonomy` (req), `name` (req), `slug`, `description`, `parent` |
| `palad/update-term` | Update a term | `term_id` (req), `taxonomy` (req), `name`, `slug`, `description` |
| `palad/delete-term` | Delete a term | `term_id` (req), `taxonomy` (req) |

---

### 5.5 Users (2)

| Ability | Description | Key parameters |
|---------|----------|-------------------|
| `palad/list-users` | List of users | `role`, `search`, `per_page` |
| `palad/update-user` | Update profile | `user_id` (req), `display_name`, `first_name`, `last_name`, `bio`, `email` |

---

### 5.6 Navigation (1)

#### `palad/list-menus`
**Input:** no parameters
**Output:** `{ menus: [{ id, name, slug, items: [{ id, title, url, type, object, parent, order }] }] }`

---

### 5.7 Site Management (6)

| Ability | Description | Input | Output |
|---------|----------|-------|--------|
| `palad/list-post-types` | Registered post types | — | `[{ name, label, public, rest_base, hierarchical }]` |
| `palad/list-taxonomies` | Registered taxonomies | — | `[{ name, label, object_type[], rest_base }]` |
| `palad/list-plugins` | Installed plugins | — | `[{ name, version, active, description }]` |
| `palad/get-option` | Read a WP option | `option_name` (req) | `{ value }` |
| `palad/update-option` | Write a WP option | `option_name` (req), `option_value` (req) | `{ updated: true }` |
| `palad/get-theme-info` | Active theme | — | `{ name, version, template, child_theme, customizer_settings }` |

---

### 5.8 Elementor (6)

| Ability | Description | Key parameters |
|---------|----------|-------------------|
| `palad/elementor-get-page-data` | JSON structure of an Elementor page (widgets, sections) | `post_id` (req) |
| `palad/elementor-update-page-data` | Update Elementor JSON data | `post_id` (req), `data` (req, JSON array) |
| `palad/elementor-global-colors` | Global colors (design system) | — |
| `palad/elementor-global-typography` | Global typography styles | — |
| `palad/elementor-list-templates` | Template library (sections, pages, popups, loops) | `type?` |
| `palad/elementor-site-templates` | Theme builder templates (header, footer, single, archive) with conditions | — |

**Important:** `elementor-update-page-data` requires valid Elementor JSON. Invalid data may break the visual presentation of the page.

---

### 5.9 Redirects (3)

| Ability | Description | Key parameters |
|---------|----------|-------------------|
| `palad/list-redirects` | All URL redirects (Redirection plugin) | — |
| `palad/create-redirect` | Create a redirect | `source_url` (req), `target_url` (req), `match_type`, `action_code` |
| `palad/delete-redirect` | Delete a redirect | `redirect_id` (req) |

---

### 5.10 Public Post Preview (2)

Integration with the **Public Post Preview** plugin — allows creating secret links for viewing drafts without authentication.

| Ability | Description | Key parameters |
|---------|----------|-------------------|
| `palad/enable-public-preview` | Enable public preview for a draft | `post_id` (req) → returns `{ preview_url, nonce }` |
| `palad/disable-public-preview` | Disable public preview | `post_id` (req) |

**Example preview URL:**
```
https://testmcpdbp.wpenginepowered.com/?p=3505&preview=true&_ppp=<nonce>
```

---

### 5.11 Self-Update (1)

#### `palad/self-update`
Updating the Palad WP Abilities plugin from a remote zip archive. Downloads, unpacks, replaces files, and reactivates the plugin.

| Parameter | Type | Required | Description |
|----------|-----|----------|----------|
| `zip_url` | string | ✅ | URL of the zip archive (must contain a `palad-wp-abilities/` folder) |

**Output:** `{ updated: true, previous_version, new_version, plugin_file }`

**Usage scenario:** after the first manual installation via the WP Admin UI, all subsequent updates can be done via an MCP call:
```
mcp-adapter-execute-ability("palad/self-update", { "zip_url": "https://example.com/palad-wp-abilities.zip" })
```

---

## 6. SDLC Workflow for WordPress

### Concept

WordPress does not have a built-in Git-style staging/preview workflow. To organize a safe development process, a combination of native WP capabilities and plugins is used.

### Workflow for a new page

```
1. Create a draft
   palad/create-post → status: "draft"
       ↓
2. Fill in the content
   palad/update-post / palad/elementor-update-page-data
       ↓
3. Generate a preview link for QA
   palad/enable-public-preview → preview_url (no authentication)
       ↓
4. QA reviews via the link
   Link format: ?p=ID&preview=true&_ppp=<nonce>
       ↓
5. Publish
   palad/update-post → status: "publish"
       ↓
6. Disable preview
   palad/disable-public-preview
```

### Workflow for updating an existing page

```
1. Create a clone (draft copy)
   palad/get-post(original_id) → save the content
   palad/create-post → title: "[DRAFT] Original Title", status: "draft"
       ↓
2. Edit the clone
   palad/update-post / palad/elementor-update-page-data
       ↓
3. Preview for QA
   palad/enable-public-preview → preview_url
       ↓
4. QA approves
       ↓
5. Apply changes to the original
   palad/update-post(original_id, content: ...) → status: "publish"
       ↓
6. Delete the clone
   palad/delete-post(clone_id, force: true)
```

### Key plugins for SDLC

| Plugin | Role in SDLC |
|--------|-------------|
| **Public Post Preview** | Secret links to drafts for QA without login |
| **Redirection** | Safe URL changes via 301 redirects during reorganization |
| **Elementor** | Visual builder — data in JSON, manageable via API |

### Security of preview links

- The link contains a unique nonce (`_ppp`), without which the preview is unavailable
- Validity period: 48 hours (configurable via the `ppp_nonce_life` filter)
- After publishing, the preview automatically stops working (the post is no longer a draft)
- It can be forcibly disabled via `palad/disable-public-preview`

---

## 7. Content Structure

### Content types

| Type | Count (published) | Description |
|-----|----------------------|----------|
| **Posts** (Insights) | 107 | Blog articles on AI, healthcare, fintech, etc. |
| **Pages** | 56 | Static pages: services, industries, technologies, about |
| **Media** | 1,087 | Images (jpg, png, webp), PDFs, other assets |

### Page hierarchy

Pages are organized into a tree structure that mirrors the navigation menu:

```
Home (id=2)
├── Services (id=13)
│   ├── AI & Machine Learning (id=1419)
│   │   └── AI Strategy Consulting (id=2935)
│   ├── AI-Enhanced Security (id=1443)
│   ├── Data & Analytics (id=1415)
│   ├── Marketing (id=1447)
│   ├── Product Development (id=1016)
│   │   ├── Software Product Discovery (id=1817)
│   │   └── System Modernization (id=1850)
│   └── Staff Augmentation (id=1454)
├── Industries (id=14)
│   ├── Consumer & Retail (id=1594)
│   ├── Financial Services (id=1420)
│   ├── Healthcare (id=617)
│   ├── Manufacturing & Supply Chain (id=1583)
│   ├── Media & Entertainment (id=1478)
│   ├── Private Equity (id=1605)
│   ├── Real Estate & Construction (id=1629)
│   ├── Tech & Software (id=1609)
│   └── Utilities (id=1502)
├── Technologies (id=15)
│   ├── Artificial Intelligence (id=1878)
│   ├── Backend (id=109)
│   │   ├── .Net (id=1806)
│   │   ├── Elixir (id=1803)
│   │   ├── Java (id=1807)
│   │   ├── Node.js (id=1813)
│   │   ├── PHP (id=1812)
│   │   ├── Python (id=1808)
│   │   └── Ruby (id=1814)
│   ├── Cloud Partners (id=1979)
│   ├── Data (id=1877)
│   ├── DevOps (id=2090)
│   ├── Frontend (id=2159)
│   │   ├── Angular (id=1740)
│   │   ├── React (id=1755)
│   │   └── Vue (id=1771)
│   └── Mobile (id=2161)
│       ├── Flutter (id=1766)
│       ├── Kotlin (id=1765)
│       ├── React Native (id=1758)
│       └── Swift (id=1769)
├── Insights (id=19, blog listing page)
├── About Us (id=18)
│   ├── DB90 (id=1298)
│   └── 3PO (id=1824)
├── Contact Us (id=20)
├── Privacy Policy (id=3)
├── Responsible AI Policy (id=2523)
├── AI Readiness Quiz (id=1858)
├── Security Automation Readiness (id=2255)
├── AWS (id=1459)
├── 3PO Secure (id=1844)
├── test (id=2423) ← test page
└── test page (id=3494) ← test page
```

---

## 8. Navigation and menu

The site has **1 menu** registered — "Menu" (id=3, slug=`menu`), containing **32 items**.

### Menu item types

| Type | Count | Description |
|-----|-----------|----------|
| `post_type` / `page` | 31 | Links to internal pages |
| `custom` | 1 | Custom link (Case Studies → `/case-studies`) |

### Top-level menu structure

| Order | Item | URL | Children |
|-------|-------|-----|---------|
| 1 | Home | `/` | — |
| 2 | Services | `/services/` | 6 sub-items |
| 9 | Industries | `/industries/` | 9 sub-items |
| 19 | Technologies | `/technologies/` | 7 sub-items |
| 27 | Case Studies | `/case-studies` | — (custom link) |
| 28 | Insights | `/insights/` | — |
| 29 | About Us | `/about/` | 2 sub-items (DB90, 3PO) |
| 32 | Contact Us | `/contact/` | — |

---

## 9. Full page catalog

### Services pages

| ID | Title | URL | Author |
|----|-----------|-----|-------|
| 13 | Services | `/services/` | Anton Dmitriev |
| 1419 | AI & Machine Learning | `/services/ai-machine-learning/` | Dualboot |
| 2935 | AI Strategy Consulting Services | `/services/ai-machine-learning/ai-consulting/` | Anton Dmitriev |
| 1443 | AI-Enhanced Security | `/services/security/` | Dualboot |
| 1415 | Data & Analytics | `/services/data/` | Dualboot |
| 1447 | Marketing | `/services/marketing/` | Dualboot |
| 1016 | Product Development | `/services/product-development/` | Anton Dmitriev |
| 1817 | Software Product Discovery | `/services/product-development/discovery/` | Anton Dmitriev |
| 1850 | System Modernization | `/services/product-development/system-modernization/` | Anton Dmitriev |
| 1454 | Staff Augmentation | `/services/staff-augmentation/` | Dualboot |

### Industries pages

| ID | Title | URL |
|----|-----------|-----|
| 14 | Industries | `/industries/` |
| 1594 | Consumer & Retail | `/industries/consumer-retail/` |
| 1420 | Financial Services | `/industries/financial-services/` |
| 617 | Healthcare | `/industries/healthcare/` |
| 1583 | Manufacturing & Supply Chain | `/industries/manufacturing-supply-chain/` |
| 1478 | Media & Entertainment | `/industries/entertainment/` |
| 1605 | Private Equity | `/industries/private-equity/` |
| 1629 | Real Estate & Construction | `/industries/real-estate/` |
| 1609 | Tech & Software | `/industries/tech-software/` |
| 1502 | Utilities | `/industries/utilities/` |

### Technologies pages

| ID | Title | URL |
|----|-----------|-----|
| 15 | Technologies | `/technologies/` |
| 1878 | Artificial Intelligence | `/technologies/ai/` |
| 109 | Backend | `/technologies/backend/` |
| 1979 | Cloud Partners | `/technologies/cloud/` |
| 1877 | Data | `/technologies/data/` |
| 2090 | DevOps | `/technologies/devops/` |
| 2159 | Frontend | `/technologies/frontend/` |
| 2161 | Mobile | `/technologies/mobile/` |
| 1740 | Angular | `/technologies/angular/` |
| 1755 | React | `/technologies/react/` |
| 1771 | Vue | `/technologies/vue/` |
| 1769 | Swift | `/technologies/swift/` |
| 1766 | Flutter | `/technologies/flutter/` |
| 1765 | Kotlin | `/technologies/kotlin/` |
| 1758 | React Native | `/technologies/react-native/` |
| 1814 | Ruby | `/technologies/ruby/` |
| 1813 | Node.js | `/technologies/node/` |
| 1812 | PHP | `/technologies/php/` |
| 1808 | Python | `/technologies/python/` |
| 1807 | Java | `/technologies/java/` |
| 1806 | .Net | `/technologies/net/` |
| 1803 | Elixir | `/technologies/elixir/` |

### Other pages

| ID | Title | URL |
|----|-----------|-----|
| 2 | Home | `/` |
| 18 | About Us | `/about/` |
| 1298 | DB90 | `/db90/` |
| 1824 | 3PO | `/3po-code-translator/` |
| 1844 | 3PO Secure | `/3po-secure/` |
| 19 | Insights | `/insights/` |
| 20 | Contact Us | `/contact/` |
| 3 | Privacy Policy | `/privacy-policy/` |
| 2523 | Responsible AI Policy | `/responsible-ai-policy/` |
| 1858 | AI Readiness Quiz | `/ai-readiness-quiz/` |
| 2255 | Security Automation Readiness | `/security-automation-readiness/` |
| 1459 | AWS | `/aws/` |

---

## 10. Blog (Insights)

### General statistics

| Metric | Value |
|-----------|----------|
| Total posts | 109 (107 published, 2 drafts) |
| URL pattern | `/insights/{slug}/` |
| Category | Insights (id=1) — the only one |
| Tags | `Featured` (0 posts), `Lead magnet` (6 posts) |
| Main authors | Dualboot (id=4), Anton Dmitriev (id=3) |

### Last 10 published posts

| Date | Title | Slug |
|------|-----------|------|
| 2026-02-17 | The "Glass Box" Copilot: Why AI in Financial Services Requires a Human-in-the-Loop Standard | `the-glass-box-copilot` |
| 2026-02-16 | The Future of Retail in the AI Era | `the-future-of-retail-in-the-ai-era` |
| 2026-02-12 | The Talent Pyramid is Crumbling: Why Traditional IT Services Can't Survive AI | `the-talent-pyramid` |
| 2026-02-12 | AI Agents: Why Demos Lie and What It Means for Production | `ai-agents-demos` |
| 2026-01-30 | Agentic Commerce Is Here: Is Your Inventory Visible to AI? | `agentic-commerce` |
| 2026-01-30 | Vibe Coding and Technical Debt: The Velocity Trap | `the-velocity-trap` |
| 2026-01-29 | Reclaiming the Bedside | `reclaiming-the-bedside` |
| 2026-01-29 | AI in Product Development: Key Trends for 2026 | `ai-in-product-development-key-trends-for-2026` |
| 2026-01-29 | 10 Questions You Must Ask AI Vendors | `10-questions-you-must-ask-ai-vendors-to-reduce-risk` |
| 2026-01-28 | The Digital Rust Breaker | `digital-rust-breaker` |

### Content themes
- AI strategy and adoption
- Healthcare and medical technology
- Fintech and financial services
- Retail and agentic commerce
- Engineering practices and product development
- Nearshore/staffing models
- Cybersecurity

---

## 11. Media library

| Metric | Value |
|-----------|----------|
| Total items | 1,087 |
| Formats | JPEG, PNG, WebP, PDF |
| Storage | WP Engine (standard directory `wp-content/uploads/`) |
| Structure | `uploads/YYYY/MM/filename` |

### Media usage types
- **Featured images** for blog posts
- **Inline images** within page content
- **PDF lead magnets** (checklists, guides) — attached to posts tagged `Lead magnet`
- **Page banners and illustrations**

### Examples of recent uploads

| ID | File | MIME | Date |
|----|-------|------|------|
| 3532 | DBP_EHR_Modernization_Readiness_Checklist-1.pdf | application/pdf | 2026-03-06 |
| 3522 | DBP_EHR_Modernization_Readiness_Checklist.pdf | application/pdf | 2026-03-05 |
| 3514 | team-of-specialists-reviewing-ecg-results-*.jpg | image/jpeg | 2026-03-05 |

---

## 12. Taxonomies

### Categories

| ID | Name | Slug | Posts |
|----|----------|------|--------|
| 1 | Insights | `insights` | 107 |

Minimal taxonomy structure — all blog posts belong to a single category.

### Tags

| ID | Name | Slug | Posts |
|----|----------|------|--------|
| 93 | Featured | `featured` | 0 |
| 83 | Lead magnet | `lead-magnet` | 6 |

The `Lead magnet` tag is used to identify posts with attached PDF guides/checklists.

---

## 13. Users and roles

| ID | Login | Display Name | Role | Email |
|----|-------|-------------|------|-------|
| 1 | dbpstaging | dbpstaging | administrator | silvina.rovella@dualbootpartners.com |
| 3 | Anton Dmitrieve | Anton Dmitriev | administrator | anton.dmitriev@dualbootpartners.com |
| 4 | dbpadmin | Dualboot | administrator | natacha.cortabarria@dualbootpartners.com |
| 5 | Juan Gomez | Juan Gomez | (no role) | juan.gomez@dualbootpartners.com |
| 6 | artem | Artem | administrator | partos0511@gmail.com |

### Content roles
- **Dualboot** (id=4) — primary author of content pages (Services, Industries, Technologies)
- **Anton Dmitriev** (id=3) — primary author of blog posts and key pages
- **Artem** (id=6) — MCP integration and technical work

---

## 14. URL routing

### Permalink structure

| Content type | Pattern | Example |
|-------------|---------|--------|
| Blog posts | `/insights/{slug}/` | `/insights/ai-agents-demos/` |
| Service pages | `/services/{slug}/` | `/services/ai-machine-learning/` |
| Service subpages | `/services/{parent}/{slug}/` | `/services/product-development/discovery/` |
| Industry pages | `/industries/{slug}/` | `/industries/healthcare/` |
| Technology hub pages | `/technologies/{slug}/` | `/technologies/ai/` |
| Technology detail pages | `/technologies/{slug}/` | `/technologies/react/` |
| About subpages | `/{slug}/` | `/db90/`, `/3po-code-translator/` |
| Case Studies | `/case-studies` | Custom link (possibly external) |
| Standalone pages | `/{slug}/` | `/responsible-ai-policy/`, `/ai-readiness-quiz/` |

### Routing notes
- Permalink structure is based on the page hierarchy (parent/child)
- Blog posts use a custom base `/insights/` instead of the default WP one
- Technology pages are not nested under hub pages by URL (all at the `/technologies/` level)
- Case Studies is a custom link in the menu, not a WP page

---

## 15. Known limitations and quirks

### MCP Protocol

| Issue | Description | Workaround |
|----------|----------|-----------|
| Empty params error | An empty object `{}` in parameters causes "invalid input" on some abilities | Pass at least one parameter (e.g. `per_page`) |
| Short session TTL | MCP sessions have a short TTL | Re-initialize for each batch of calls |
| Schema mismatch | `core/get-environment-info` and `core/get-user-info` may return a schema error via `get-ability-info` | Use data from `discover-abilities` + a direct call through `execute-ability` |
| Type filter issue | `palad/list-posts` with `type=post` and `type=page` may return identical results | Use the `post_type` parameter, verify the results |
| Elementor data sensitivity | `elementor-update-page-data` with invalid JSON breaks the page visuals | Always run `elementor-get-page-data` before updating, then modify and return it |
| WP Engine WAF | Large POST requests with PHP code are blocked by the Cloudflare WAF | Use SFTP or the self-update ability to deploy code |
| Plugin install via REST | `/wp/v2/plugins` supports only plugins from wordpress.org by slug | Do the first install via WP Admin UI, then use `palad/self-update` |

### Content

| Issue | Description |
|----------|----------|
| Test pages | Pages "test" (id=2423) and "test page" (id=3494) are present — junk data |
| Minimal taxonomy | All posts in one category, no thematic segmentation |
| Unused tag | `Featured` (id=93) has 0 attached posts |
| User without a role | Juan Gomez (id=5) has no assigned role |

### Deploy and updates

| Issue | Description | Workaround |
|----------|----------|-----------|
| No SFTP on prod | Production sites may not have SFTP access | First install via WP Admin → Plugins → Upload. Then — `palad/self-update` |
| mu-plugins restricted | WP Engine does not allow writing to `wp-content/mu-plugins` via SFTP | Install as a regular plugin in `wp-content/plugins/` |
| Public Post Preview TTL | Preview links live for 48h by default | Configurable via the `ppp_nonce_life` filter |

---

## 16. Diagrams

### Interaction architecture

```
┌──────────────────────┐
│    Cursor IDE         │
│  (MCP Client)         │
└──────────┬───────────┘
           │ MCP Protocol
           │ (streamable HTTP + Basic Auth)
           ▼
┌──────────────────────────────────────────────┐
│  WP Engine: testmcpdbp.wpenginepowered.com   │
│                                               │
│  ┌─────────────────────────────────────────┐  │
│  │ /wp-json/mcp/mcp-adapter-default-server │  │
│  │          MCP Adapter Plugin              │  │
│  └──────────────┬──────────────────────────┘  │
│                 │ WP Abilities API             │
│  ┌──────────────▼──────────────────────────┐  │
│  │      Palad WP Abilities (v2.2.0)        │  │
│  │  ┌─────────┐ ┌──────────┐ ┌──────────┐ │  │
│  │  │ Posts   │ │ Media    │ │ Terms    │ │  │
│  │  │ (CRUD+  │ │ (List/   │ │ (CRUD)   │ │  │
│  │  │  Meta)  │ │  Upload) │ │          │ │  │
│  │  └─────────┘ └──────────┘ └──────────┘ │  │
│  │  ┌─────────┐ ┌──────────┐ ┌──────────┐ │  │
│  │  │ Users   │ │ Elementor│ │ Redirects│ │  │
│  │  │ (List/  │ │ (6 tools)│ │ (CRUD)   │ │  │
│  │  │  Update)│ │          │ │          │ │  │
│  │  └─────────┘ └──────────┘ └──────────┘ │  │
│  │  ┌─────────┐ ┌──────────┐ ┌──────────┐ │  │
│  │  │ Site    │ │ Preview  │ │ Self-    │ │  │
│  │  │ Mgmt(6) │ │ (2 tools)│ │ Update   │ │  │
│  │  └─────────┘ └──────────┘ └──────────┘ │  │
│  └─────────────────────────────────────────┘  │
│                 │                              │
│  ┌──────────────▼──────────────────────────┐  │
│  │     WordPress Core (6.9.1)               │  │
│  │     + 3 Core Abilities                   │  │
│  │     (site-info, user-info, env-info)     │  │
│  └──────────────┬──────────────────────────┘  │
│                 │                              │
│  ┌──────────────▼──────────────────────────┐  │
│  │         MySQL 8.4.7-7                    │  │
│  └─────────────────────────────────────────┘  │
└──────────────────────────────────────────────┘
```

### Ability call flow

```
1. Client → mcp-adapter-discover-abilities
   ← List of 38 abilities

2. Client → mcp-adapter-get-ability-info(ability_name)
   ← Input/output schema + metadata

3. Client → mcp-adapter-execute-ability(ability_name, parameters)
   ← { success: true, data: {...} }
   or
   ← { success: false, error: "..." }
```

### Content map

```
                    ┌─────────┐
                    │  Home   │
                    └────┬────┘
         ┌───────┬───────┼───────┬──────────┐
         ▼       ▼       ▼       ▼          ▼
    ┌─────────┐ ┌────┐ ┌─────┐ ┌──────┐ ┌───────┐
    │Services │ │Ind.│ │Tech.│ │About │ │Contact│
    │  (6+3)  │ │ (9)│ │(7+15)│ │ (2)  │ │       │
    └────┬────┘ └────┘ └──┬──┘ └──────┘ └───────┘
         │                │
    subpages         tech detail
    (AI Consulting,  pages (React,
     Discovery,       Python, etc.)
     Modernization)

    ┌───────────┐     ┌─────────────┐
    │  Insights │────▶│ 107 posts   │
    │  (listing)│     │ /insights/* │
    └───────────┘     └─────────────┘

    ┌───────────────────────────┐
    │     Media Library         │
    │     1,087 items           │
    │  (jpg, png, webp, pdf)    │
    └───────────────────────────┘
```
