"""One-shot text agent implementation using BaseOpenRouterAgent."""

from typing import Any

from agents.common.base_openrouter_agent import BaseOpenRouterAgent
from models.telemetry import TelemetryContext

from .configuration import OneShotTextAgentConfig


class OneShotTextAgent[T](BaseOpenRouterAgent[T]):
    """Agent that performs single LLM calls with message construction."""

    def __init__(
        self,
        agent_name: str,
        telemetry: TelemetryContext,
        config: OneShotTextAgentConfig | None = None,
        structured_output_type: type[T] | None = None,
    ):
        super().__init__(agent_name, telemetry, config, structured_output_type)
        self.llm = config.llm

    def invoke(
        self,
        system_prompt: str,
        user_prompt: str,
        metadata: dict[str, Any] | None = None,
        structured_output_schema: type | None = None,
    ) -> Any:
        """Invoke LLM with system and user prompts using sync client."""
        messages = [
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": user_prompt},
        ]

        return self.invoke_openrouter(
            llm=self.llm,
            messages=messages,
            metadata=metadata,
            structured_output_schema=structured_output_schema,
        )
