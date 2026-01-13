"""Mixture of Experts agent implementation using 3-consensus scheme."""

from typing import Any, TypeVar

from core.logging import logger

from agents.common.base.configuration import BaseLLMConfig
from agents.common.base_openrouter_agent import BaseOpenRouterAgent
from config import settings
from models.telemetry import TelemetryContext

from .configuration import MixtureOfExpertsAgentConfig

T = TypeVar("T")


class MixtureOfExpertsAgent[T](BaseOpenRouterAgent[T]):
    """Base agent that implements 3-expert consensus pattern using direct OpenRouter calls."""

    def __init__(
        self,
        agent_name: str,
        telemetry: TelemetryContext,
        config: MixtureOfExpertsAgentConfig,
    ):
        super().__init__(agent_name, telemetry, config)

        self.expert1_llm_config = config.expert1_llm
        self.expert2_llm_config = config.expert2_llm
        self.expert3_llm_config = config.expert3_llm
        self.judge_llm_config = config.judge_llm

    def invoke_consensus(
        self,
        content: str,
        expert_prompt: str,
        judge_prompt: str,
        structured_output_schema: type[T],
        metadata: dict[str, Any] | None = None,
    ) -> T:
        """
        Execute 3-expert consensus analysis with concurrent expert calls.

        Args:
            content: Input content to analyze
            expert_prompt: Prompt for individual expert analysis
            judge_prompt: Prompt for consensus judgment
            structured_output_schema: Pydantic model for structured output
            metadata: Additional metadata for telemetry

        Returns:
            Consensus result as structured output
        """
        logger.debug(f"Starting 3-expert consensus analysis in {self.agent_name}")

        # Step 1: Run 3 expert analyses using ThreadPoolExecutor
        from concurrent.futures import ThreadPoolExecutor

        expert_configs = [
            (1, self.expert1_llm_config),
            (2, self.expert2_llm_config),
            (3, self.expert3_llm_config),
        ]

        def call_single_expert(
            expert_id: int, expert_config: BaseLLMConfig
        ) -> tuple[int, T]:
            """Call a single expert and return (expert_id, result)."""
            logger.debug(f"Expert {expert_id} called ({expert_config.model})")

            expert_metadata = {
                **(metadata or {}),
                "expert_id": expert_id,
                "pass": "expert_analysis",
            }

            result = self._invoke_expert(
                content=content,
                prompt=expert_prompt,
                llm=expert_config,
                structured_output_schema=structured_output_schema,
                metadata=expert_metadata,
                parallel_tool_calls=False,
            )
            logger.debug(f"Expert {expert_id} responded")
            return (expert_id, result)

        # Execute experts with single worker for deterministic order in tests
        # Can be changed to max_workers=3 for parallel execution in production
        with ThreadPoolExecutor(
            max_workers=settings.concurrency.mixture_of_experts
        ) as executor:
            # Submit in order and keep list reference for deterministic retrieval
            futures = [
                executor.submit(call_single_expert, expert_id, config)
                for expert_id, config in expert_configs
            ]

            # Wait for results in submission order (deterministic)
            expert_analyses = [future.result()[1] for future in futures]

        # Step 2: Judge consensus (sync)
        judge_input = self._format_judge_input(content, expert_analyses)
        judge_metadata = {
            **(metadata or {}),
            "pass": "consensus_judge",
        }

        consensus_result = self._invoke_expert(
            content=judge_input,
            prompt=judge_prompt,
            llm=self.judge_llm_config,
            structured_output_schema=structured_output_schema,
            metadata=judge_metadata,
        )
        logger.debug("Judge responded")

        logger.debug(f"Consensus complete in {self.agent_name}")
        return consensus_result

    def _invoke_expert(
        self,
        content: str,
        prompt: str,
        llm: BaseLLMConfig,
        structured_output_schema: type[T],
        metadata: dict[str, Any] | None = None,
        parallel_tool_calls: bool = False,
    ) -> T:
        """Invoke a single expert with specific LLM configuration (sync version)."""

        messages = [
            {"role": "system", "content": prompt},
            {"role": "user", "content": content},
        ]

        return self.invoke_openrouter(
            llm=llm,
            messages=messages,
            metadata=metadata,
            structured_output_schema=structured_output_schema,
            parallel_tool_calls=parallel_tool_calls,
        )

    def _format_judge_input(self, content: str, analyses: list[T]) -> str:
        """Format input for consensus judge including original content and expert analyses."""
        formatted_analyses = "\n\n".join(
            [
                f"Expert Analysis {i + 1}:\n{analysis.model_dump_json(indent=2)}"
                for i, analysis in enumerate(analyses)
            ]
        )

        return f"""Original Content:
```
{content}
```

Expert Analyses:
{formatted_analyses}"""
