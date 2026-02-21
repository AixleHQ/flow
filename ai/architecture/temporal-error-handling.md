# Temporal Error Handling

> Error-handling principles in Temporal workflows and activities.
> Based on the official Ruby SDK documentation and an analysis of best practices.

## Two types of failures in a Workflow

| Type | When it occurs | Temporal behavior |
|-----|-----------------|---------------------|
| **Workflow Task Failure** | Workflow code throws a non-Temporal exception (`RuntimeError`, `NoMethodError`, etc.) | The task retries indefinitely. The workflow stays Open. Considered a bug that can be fixed by a deploy |
| **Workflow Execution Failure** | Workflow code throws `Temporalio::Error::Failure` or its descendants (`ApplicationError`, `ActivityError`, `CanceledError`, `Timeout::Error`) | The workflow is marked Failed. Execution stops |

**Rule**: a workflow must never fail because of an activity error. An Activity Failure arrives in the workflow as `ActivityError` — a descendant of `Failure`. If it is not caught, the workflow will fail. If caught, you can make a decision (retry, compensate, cleanup, fail).

## Errors in an Activity

Any exception in an Activity is automatically converted by Temporal into an `ApplicationError`:
- `type` — the class name of the original exception
- `message` — error text
- `non_retryable` — false (default, will be retried)

You can explicitly raise `ApplicationError` to control `type`, `non_retryable`, `category`, `details`.

### Retryable vs Non-retryable

| Error type | `non_retryable` | When to use |
|------------|-----------------|---------------------|
| **Retryable** | `false` | Transient failures: network, rate limit, temporary service unavailability |
| **Non-retryable** | `true` | Permanent errors: invalid input, missing resource, business-logic violation |

### Benign exceptions (Category::BENIGN)

Errors that are **expected** during normal system operation but are still errors (the Activity completes unsuccessfully).

Effect of `category: BENIGN`:
- The Activity failure log is downgraded from ERROR to **DEBUG**
- **Does not increment** the `temporal_activity_execution_failed` metric
- **Does not set** OpenTelemetry status = ERROR

Typical candidates for benign:
- The container is already deleted at cleanup time (race condition)
- `RecordNotFound` due to a race between processes
- A polling activity that has not yet received its result
- Errors when deleting already-nonexistent resources

**Important**: benign does not override the retryable/non-retryable semantics. Benign retryable — will be retried, but silently. Benign non-retryable — will fail, but without noise in the metrics.

## Activity → Workflow: wrapping in ActivityError

When an Activity fails (all retries exhausted or `non_retryable: true`), the Workflow receives **not** the original `ApplicationError`, but a `Temporalio::Error::ActivityError`:

```
ActivityError (Temporal system wrapper)
  └── cause: ApplicationError (our error)
        ├── type: "Docker::Error::NotFoundError"
        ├── message: "Container not found"
        ├── non_retryable: true
        └── category: BENIGN
```

To make decisions in the workflow, you need to check `error.cause.type` or `error.cause.class`.

## Principles for Workflow code

### 1. Catch specific Temporal errors, not StandardError

`rescue StandardError` in workflow code is dangerous: it will also catch bugs in the workflow code (NilMethodError), which should cause a Workflow Task Failure and be retried until fixed.

Correct:
- `rescue Temporalio::Error::ActivityError` — for errors from an Activity
- `rescue Temporalio::Error::CanceledError` — for cancellation
- `rescue Temporalio::Error::ApplicationError` — if we raise it ourselves

### 2. Cleanup must always run

The ensure-cleanup pattern: catch the execution error, save it, run cleanup, then make a decision — fail the workflow or complete with a result.

### 3. Do not silently swallow cleanup errors

If cleanup fails — this must be reflected in the workflow result. Lost cleanup errors lead to stuck resources (containers, volumes) with no trace in the logs.

### 4. Workflow Execution Failure — a deliberate decision

The workflow should fail (Failed) only when we **explicitly** decide to do so via `raise ApplicationError`. All other errors are either compensable situations or code bugs.

## Principles for Activity code

### 1. Wrap errors through a single helper

All exceptions from external systems (Docker, K8s, HTTP) are wrapped in `ApplicationError` via `TemporalExceptions.wrap`. This gives control over `type`, `non_retryable`, `category`.

### 2. Classify errors along three axes

| Axis | Options | Question |
|-----|----------|--------|
| Retryable | yes / no | Can a repeated call help? |
| Benign | yes / no | Is this an expected situation during normal operation? |
| Type | string | By which type will the workflow make its decision? |

### 3. Preserve the cause chain

Ruby automatically sets `cause` on `raise` inside a `rescue` block. The Temporal SDK serializes this chain. You do not need to pass `cause` manually — it is enough to raise a new exception inside `rescue`.

### 4. Activity Base — a single point of handling

The Activity base class intercepts common Rails errors (`RecordNotFound`, `RecordInvalid`) and wraps them. Specific errors (Docker, K8s) are intercepted in the concrete Activities.

## Error classification by layer

```
┌─────────────────────────────────────────────┐
│  Workflow                                   │
│  rescue ActivityError → decision:           │
│    - compensate / cleanup / fail            │
│  Do NOT catch StandardError                │
├─────────────────────────────────────────────┤
│  Activity                                   │
│  rescue → TemporalExceptions.wrap(          │
│    retryable: bool, benign: bool            │
│  )                                          │
├─────────────────────────────────────────────┤
│  ContainerService (domain)                  │
│  PhaseError wraps the original              │
├─────────────────────────────────────────────┤
│  Strategy (infrastructure)                  │
│  Raises domain errors or propagates         │
│  runtime errors                             │
├─────────────────────────────────────────────┤
│  Runtime (Docker / K8s gems)                │
│  Docker::Error::*, Kubeclient::HttpError    │
└─────────────────────────────────────────────┘
```

## Decision table: what to do with an error

| Error | retryable | benign | non_retryable | Rationale |
|--------|-----------|--------|---------------|-------------|
| Docker timeout / network | yes | no | no | Transient failure, retry helps |
| Docker API 500 | yes | no | no | Docker daemon server error |
| Container NotFound (during cleanup) | no | **yes** | yes | Container already deleted — expected |
| Container NotFound (during exec) | no | no | yes | Real problem — the container disappeared |
| Image pull failed (registry down) | yes | no | no | Transient, retry helps |
| Invalid input / ArgumentError | no | no | yes | Pointless to retry |
| RecordNotFound (race condition) | no | **yes** | yes | Session deleted by another process |
| RecordNotFound (real bug) | no | no | yes | Data does not exist, needs investigation |
| Ports not ready timeout | no | no | yes | Container did not start |
| Signal timeout in workflow | — | — | — | Not an Activity error; the workflow decides itself |

## Antipatterns

1. **`rescue StandardError` in a Workflow** — catches code bugs that should cause a Task Failure
2. **Swallowing cleanup errors** — leads to resource leaks without a trace
3. **All errors as plain ApplicationError** — noise in the metrics, impossible to distinguish expected from a failure
4. **Inheriting from ApplicationError** — the SDK is not designed for this; use `type` for classification
5. **Raising ActivityError manually** — this is Temporal's system wrapper, not intended for user code

## Links

- [Temporal Ruby SDK: Failure Detection](https://docs.temporal.io/develop/ruby/failure-detection)
- [Temporal Ruby SDK: Benign Exceptions](https://docs.temporal.io/develop/ruby/benign-exceptions)
- [Temporal Failures Reference](https://docs.temporal.io/references/failures)
- [Ruby API: ApplicationError](https://ruby.temporal.io/Temporalio/Error/ApplicationError.html)
- [Ruby API: ApplicationError::Category](https://ruby.temporal.io/Temporalio/Error/ApplicationError/Category.html)
