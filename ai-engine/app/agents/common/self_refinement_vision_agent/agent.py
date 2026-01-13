"""Self-refinement vision agent implementation."""

from typing import Any, Literal

from langchain_core.messages import BaseMessage, HumanMessage
from langchain_openai import ChatOpenAI
from langgraph.graph import END, START, StateGraph
from core.logging import logger

from agents.common.base import BaseAgent
from agents.common.base.configuration import BaseLLMConfig
from llm.llm_factory import LLMFactory
from models.telemetry import TelemetryContext

from .configuration import SelfRefinementVisionConfig


class SelfRefinementVisionAgent[T](BaseAgent[T]):
    """Base agent for self-refinement vision analysis using LangGraph."""

    def __init__(
        self,
        agent_name: str,
        telemetry: TelemetryContext,
        state_schema: type,
        config: SelfRefinementVisionConfig,
        structured_output_type: type[T] | None = None,
    ):
        super().__init__(agent_name, telemetry, structured_output_type, config)

        self.state_schema = state_schema
        self.vision_model = self._create_langchain_llm(config.vision_model)
        self.critic_model = self._create_langchain_llm(config.critic_model)
        self.summary_model = self._create_langchain_llm(config.summary_model)

        # Build sync graph only (threads pool uses sync path)
        self.graph = self._build_graph()

    def _create_langchain_llm(self, llm_config: BaseLLMConfig) -> ChatOpenAI:
        """Create LangChain LLM from configuration."""
        return LLMFactory.create_langchain_openrouter_llm(
            model=llm_config.model,
            temperature=llm_config.temperature,
            max_tokens=llm_config.max_tokens,
        )

    def _invoke_langchain_llm(
        self,
        llm: ChatOpenAI,
        messages: list[BaseMessage],
        metadata: dict[str, Any] | None = None,
    ) -> BaseMessage:
        """Invoke LangChain LLM with telemetry."""
        callback_handler = LLMFactory.create_langchain_callback_handler()

        config = self.build_langchain_config(
            callback_handler=callback_handler,
            metadata=metadata,
        )

        return llm.invoke(messages, config=config)

    def _build_graph(self) -> StateGraph:
        """Build the LangGraph workflow for self-reflection analysis."""

        builder = StateGraph(self.state_schema, self.config)

        builder.add_node("analyze", self._analyze_vision)
        builder.add_node("judge", self._judge_analysis)
        builder.add_node("refine", self._refine_analysis)

        builder.add_edge(START, "analyze")
        builder.add_edge("analyze", "judge")
        builder.add_conditional_edges(
            "judge",
            self._should_continue,
            {"refine": "refine", "complete": END},
        )
        builder.add_edge("refine", "judge")

        return builder.compile()

    def invoke(self, state: dict, metadata: dict[str, Any] | None = None) -> dict:
        langfuse_handler = LLMFactory.create_langchain_callback_handler()

        config = self.build_langchain_config(
            callback_handler=langfuse_handler,
            metadata=metadata,
        )

        return self.graph.invoke(state, config)

    def _analyze_vision(
        self,
        state,
    ) -> dict:
        """Generate analysis from screenshot - starts the conversation."""
        formatted_prompt = self._format_analysis_prompt(state)
        image_url = self.get_base64_url(state["image_data"], state["screenshot_path"])

        human_message = HumanMessage(
            content=[
                {"type": "text", "text": formatted_prompt},
                {
                    "type": "image_url",
                    "image_url": {"url": image_url},
                },
            ],
        )

        response = self._invoke_langchain_llm(self.vision_model, [human_message])

        return {
            "messages": [human_message, response],
            "functional_groups": response.content,
            "refinement_attempts": 0,
        }

    def _format_analysis_prompt(self, state) -> str:
        """Format the initial analysis prompt. Override in subclasses."""
        raise NotImplementedError("Subclasses must implement _format_analysis_prompt")

    def _judge_analysis(self, state) -> dict:
        """Judge the quality of analysis - external evaluation, no conversation."""
        current_analysis = state["functional_groups"]
        judge_prompt = self._format_judge_prompt(state)
        image_url = self.get_base64_url(state["image_data"], state["screenshot_path"])

        critique_message = HumanMessage(
            content=[
                {
                    "type": "text",
                    "text": judge_prompt,
                },
                {
                    "type": "image_url",
                    "image_url": {"url": image_url},
                },
            ],
        )

        judge_response = self._invoke_langchain_llm(
            self.critic_model, [critique_message]
        )

        response_text = judge_response.content.strip().upper()
        if "APPROVED" in response_text:
            logger.info("✅ Analysis approved")
            return {
                "analysis_complete": True,
                "refinement_attempts": state.get("refinement_attempts", 0),
            }

        attempt_num = state.get("refinement_attempts", 0) + 1
        logger.info(f"⚠️ Judge requested improvements (attempt #{attempt_num})")
        logger.debug(f"📊 Analysis length: {len(current_analysis)} chars")
        logger.debug(f"🔍 Critique: {judge_response.content}")
        return {
            "critique": judge_response.content,
            "analysis_complete": False,
            "refinement_attempts": attempt_num,
        }

    def _format_judge_prompt(self, state) -> str:
        """Format the judge prompt. Override in subclasses."""
        raise NotImplementedError("Subclasses must implement _format_judge_prompt")

    def _should_continue(
        self,
        state,
    ) -> Literal["refine", "complete"]:
        """Decide whether to refine or complete the analysis."""
        max_attempts = self.config.max_refinement_attempts

        if state.get("analysis_complete", False):
            return "complete"
        if state.get("refinement_attempts", 0) >= max_attempts:
            logger.warning(f"⚠️ Max refinement attempts ({max_attempts}) reached")
            return "complete"
        return "refine"

    def _refine_analysis(self, state) -> dict:
        """Refine the analysis based on judge feedback - continues the conversation."""
        refinement_prompt = self._format_refinement_prompt(state)
        image_url = self.get_base64_url(state["image_data"], state["screenshot_path"])

        refinement_message = HumanMessage(
            content=[
                {"type": "text", "text": refinement_prompt},
                {
                    "type": "image_url",
                    "image_url": {"url": image_url},
                },
            ],
        )

        conversation = state["messages"] + [refinement_message]
        response = self._invoke_langchain_llm(self.vision_model, conversation)

        attempt_num = state.get("refinement_attempts", 0)
        logger.info(f"🔄 Refinement attempt #{attempt_num}")
        logger.debug(f"📝 Critique length: {len(state['critique'])} chars")
        logger.debug(f"✏️ Refined analysis length: {len(response.content)} chars")
        logger.debug(f"💬 Conversation length: {len(conversation)} messages")

        return {
            "messages": [refinement_message, response],
            "functional_groups": response.content,
        }

    def _format_refinement_prompt(self, state) -> str:
        """Format the refinement prompt. Override in subclasses."""
        raise NotImplementedError("Subclasses must implement _format_refinement_prompt")
