"""Enhanced Langfuse CallbackHandler with OpenRouter cost tracking.

Extends Langfuse's CallbackHandler to extract cost information and metadata
from OpenRouter responses, similar to the langfuse.openai integration.

Usage:
    from core.utils.patches import CostTrackingCallbackHandler

    handler = CostTrackingCallbackHandler()
"""

from typing import Any
from uuid import UUID

from langfuse.langchain import CallbackHandler


class CostTrackingCallbackHandler(CallbackHandler):
    """Enhanced Langfuse CallbackHandler with OpenRouter cost tracking."""

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self._current_response = None

    def _parse_openrouter_data(self, response: Any) -> dict[str, Any]:
        """Parse OpenRouter cost and metadata from LLM response."""
        if not hasattr(response, "llm_output") or not response.llm_output:
            return {}

        llm_output = response.llm_output
        token_usage = llm_output.get("token_usage", {})

        update_params = {}

        # Extract cost details
        cost = token_usage.get("cost")
        if cost and cost > 0:
            cost_details = token_usage.get("cost_details", {})
            update_params["cost_details"] = {
                "input": cost_details.get("upstream_inference_prompt_cost", 0),
                "output": cost_details.get("upstream_inference_completions_cost", 0),
                "total": cost,
            }

        # Extract metadata
        metadata = {}
        if "is_byok" in token_usage:
            metadata["openrouter_is_byok"] = token_usage["is_byok"]

        if "cache_discount" in token_usage:
            metadata["openrouter_cache_discount"] = token_usage["cache_discount"]

        for field in ["system_fingerprint", "service_tier", "id"]:
            if field in llm_output:
                metadata[f"openrouter_{field}"] = llm_output[field]

        if metadata:
            update_params["metadata"] = metadata

        return update_params

    def _detach_observation(self, run_id: UUID) -> Any | None:
        """Override to inject OpenRouter data before parent finalizes the generation."""
        generation = super()._detach_observation(run_id)

        if generation and self._current_response:
            openrouter_params = self._parse_openrouter_data(self._current_response)
            if openrouter_params:
                generation.update(**openrouter_params)

        return generation

    def on_llm_end(
        self,
        response: Any,
        *,
        run_id: UUID,
        parent_run_id: UUID | None = None,
        **kwargs: Any,
    ) -> Any:
        """Store response and delegate to parent for all processing."""
        self._current_response = response

        try:
            return super().on_llm_end(
                response, run_id=run_id, parent_run_id=parent_run_id, **kwargs
            )
        finally:
            self._current_response = None
