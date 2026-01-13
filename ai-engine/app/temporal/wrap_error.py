"""Custom exceptions for Temporal activities.

Based on: https://docs.temporal.io/references/failures
"""

from temporalio.exceptions import ApplicationError


class RetryableError(ApplicationError):
    """Retryable error - will be retried according to retry policy.

    Use for transient errors:
    - Network timeouts
    - Rate limits
    - Temporary service unavailability

    Example:
        if rate_limited:
            raise RetryableError("Rate limit exceeded, retry in 60s")
    """

    def __init__(self, message: str, type: str):
        super().__init__(
            message,
            type=type,
            non_retryable=False,  # Will retry
        )


class NonRetryableError(ApplicationError):
    """Non-retryable error - activity will fail immediately without retries.

    Use for permanent errors:
    - Invalid input data
    - Missing required resources
    - Business logic violations

    Example:
        if not files_found:
            raise NonRetryableError("No files found for categories", type="NoFilesError")
    """

    def __init__(self, message: str, type: str):
        super().__init__(
            message,
            type=type,
            non_retryable=True,  # Won't retry
        )


def wrap_error(error: Exception, retryable: bool = True) -> ApplicationError:
    """Wrap a standard Python exception into Temporal ApplicationError.

    Args:
        error: Original exception (ValueError, KeyError, etc)
        retryable: Whether error should be retried

    Returns:
        ApplicationError with appropriate settings

    Example:
        try:
            value = data['required_field']
        except KeyError as e:
            raise wrap_error(e, retryable=False) from e
    """
    error_class = RetryableError if retryable else NonRetryableError

    return error_class(
        str(error),
        type(error).__name__,
    )
