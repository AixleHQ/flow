"""Workflow helper functions - safe for Temporal sandbox."""

from datetime import timedelta
from typing import Any

from temporalio import workflow
from temporalio.common import RetryPolicy

from constants.workflows import Workflows, ActivityDef


# Default configurations for different activity types
DEFAULT_RETRY_POLICY = RetryPolicy(
    maximum_attempts=8,
    initial_interval=timedelta(seconds=5),
    backoff_coefficient=3.0,
)

DEFAULT_TIMEOUT = timedelta(minutes=10)
EXTENDED_TIMEOUT = timedelta(minutes=30)


async def execute_activity(
    activity: ActivityDef,
    *args,
    retry_count: None | int = None,
    timeout: timedelta | None = None,
    **kwargs,
) -> Any:
    """Execute activity with smart defaults.

    Usage:
        from workflows.helpers import execute_activity
        from constants import Workflows

        result = await execute_activity(
            Workflows.workspace_setup.activities.get_presets,
            workspace_id,
        )

        # With custom timeout
        result = await execute_activity(
            Workflows.asset_codebase_processing.activities.analyze_file,
            {'file_id': 1, 'codebase_id': 1},
            timeout=timedelta(minutes=5),
        )

    Args:
        activity: ActivityDef from Workflows constants
        *args: Positional arguments for activity
        timeout: Override default timeout
        retry_policy: Override default retry policy
        **kwargs: Additional options for execute_activity

    Returns:
        Activity result
    """
    if retry_count is None:
        retry_policy = DEFAULT_RETRY_POLICY
    else:
        retry_policy = RetryPolicy(
            maximum_attempts=retry_count, initial_interval=timedelta(seconds=5)
        )

    activity_timeout = timeout or DEFAULT_TIMEOUT

    return await workflow.execute_activity(
        activity.name,
        *args,
        retry_policy=retry_policy,
        task_queue=activity.task_queue,
        start_to_close_timeout=activity_timeout,
        **kwargs,
    )


# Shared activity helpers - reusable across all asset workflows
async def finalize_asset(asset_id: int) -> dict:
    return await execute_activity(
        Workflows.asset_document_processing.activities.shared_finalize_asset,
        asset_id,
    )


async def fail_asset(asset_id: int) -> dict:
    return await execute_activity(
        Workflows.asset_document_processing.activities.shared_fail_asset,
        asset_id,
    )
