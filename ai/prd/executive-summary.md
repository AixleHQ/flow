# Executive Summary

## Product Vision

**Palad** — a cloud platform for orchestrating AI coding agents with a workflow system. The name comes from the myth of the Palladium — a sacred object that was the "anchor" of Troy's defense system.

## Problem Statement

Teams already use AI coding agents (Claude Code, Cursor, Codex) locally, but they run into problems:
- **No centralization** — everyone configures agents on their own
- **No sharing** — workflows, prompts, and settings are not reused
- **No transparency** — it is unclear how much the agents' work costs
- **No orchestration** — there are no step-by-step workflows with artifacts

## Solution

Palad solves these problems through:
- **Agent Orchestration** — a single platform for different agents in Docker
- **Workflow Engine** — BMAD-style step-by-step execution with artifacts
- **Billing & Analytics** — an MITM proxy for accurate token accounting
- **Shared Configuration** — centralized workflows, prompts, secrets

## Target Users

- **Primary:** A services company (~70 people), fixed-bid projects
- **Initial Scope:** An internal tool for the team
- **Future:** A public SaaS for external clients

## Key Differentiator

Palad is not yet another AI coding tool, but an **orchestration layer** for existing agents. We do not compete with Cursor or Claude Code — we make their use centralized and transparent.

## MVP Timeline

**8-12 weeks** with a team of 3 people (Artem, Andrey, Alexander)

---
