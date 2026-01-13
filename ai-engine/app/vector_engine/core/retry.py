"""Universal retry logic for vector operations."""

import time
from collections.abc import Callable
from functools import wraps
from typing import Any

from core.logging import logger
from pydantic import BaseModel, Field

from .exceptions import VectorEngineError


class RetryConfig(BaseModel):
    """Configuration for retry logic."""

    max_attempts: int = Field(default=3, description="Maximum retry attempts")
    base_delay: float = Field(
        default=1.0, description="Base delay between retries in seconds"
    )
    max_delay: float = Field(default=30.0, description="Maximum delay between retries")
    backoff_multiplier: float = Field(
        default=2.0, description="Exponential backoff multiplier"
    )

    # Exceptions that should trigger retries
    retryable_exceptions: tuple[type[Exception], ...] = Field(
        default=(ConnectionError, TimeoutError),
        description="Exception types that should trigger retries",
    )


def with_retry(
    config: RetryConfig | None = None, operation_name: str = "vector_operation"
) -> Callable:
    """
    Decorator for adding retry logic to vector operations.

    Usage:
        @with_retry(RetryConfig(max_attempts=5), "index_document")
        def risky_operation():
            # operation that might fail
            pass
    """
    if config is None:
        config = RetryConfig()

    def decorator(func: Callable) -> Callable:
        @wraps(func)
        def wrapper(*args, **kwargs) -> Any:
            last_exception = None

            for attempt in range(1, config.max_attempts + 1):
                try:
                    logger.debug(
                        f"Attempting {operation_name} (attempt {attempt}/{config.max_attempts})"
                    )
                    result = func(*args, **kwargs)

                    if attempt > 1:
                        logger.info(f"{operation_name} succeeded on attempt {attempt}")

                    return result

                except config.retryable_exceptions as e:
                    last_exception = e

                    if attempt == config.max_attempts:
                        logger.error(
                            f"{operation_name} failed after {config.max_attempts} attempts: {e}"
                        )
                        break

                    # Calculate delay with exponential backoff
                    delay = min(
                        config.base_delay
                        * (config.backoff_multiplier ** (attempt - 1)),
                        config.max_delay,
                    )

                    logger.warning(
                        f"{operation_name} failed on attempt {attempt}, retrying in {delay:.1f}s: {e}"
                    )
                    time.sleep(delay)

            # All retries exhausted
            raise VectorEngineError(
                f"{operation_name} failed after {config.max_attempts} attempts"
            ) from last_exception

        return wrapper

    return decorator


class RetryableOperation:
    """
    Context manager for retryable operations.
    Alternative to decorator for more complex scenarios.
    """

    def __init__(
        self, config: RetryConfig | None = None, operation_name: str = "operation"
    ):
        self.config = config or RetryConfig()
        self.operation_name = operation_name
        self.attempt = 0

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        if exc_type is None:
            return False  # No exception, continue normally

        # Check if this is a retryable exception
        if not issubclass(exc_type, self.config.retryable_exceptions):
            return False  # Let non-retryable exceptions propagate

        self.attempt += 1

        if self.attempt >= self.config.max_attempts:
            logger.error(
                f"{self.operation_name} failed after {self.config.max_attempts} attempts"
            )
            return False  # Let the exception propagate

        # Calculate delay
        delay = min(
            self.config.base_delay
            * (self.config.backoff_multiplier ** (self.attempt - 1)),
            self.config.max_delay,
        )

        logger.warning(
            f"{self.operation_name} failed on attempt {self.attempt}, retrying in {delay:.1f}s: {exc_val}"
        )
        time.sleep(delay)

        return True  # Suppress the exception, retry
