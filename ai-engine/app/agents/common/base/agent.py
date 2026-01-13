import base64
from typing import Any, TypeVar

from models.telemetry import TelemetryContext

from .configuration import BaseAgentConfig

T = TypeVar("T")


class BaseAgent[T]:
    """Unified base class for all agents."""

    def __init__(
        self,
        agent_name: str,
        telemetry: TelemetryContext,
        structured_output_type: type[T] | None = None,
        config: BaseAgentConfig | None = None,
    ):
        self.agent_name = agent_name
        self.telemetry = telemetry
        self.config = config
        self.prompts = self._load_prompts()
        self.structured_output_type = structured_output_type

    def _load_prompts(self) -> dict[str, str]:
        """Load all prompts for this agent."""
        return {}

    def get_base64_url(self, image_data: bytes, file_path: str) -> str:
        """Create a base64 data URL from image data and file path."""
        encoded_data = base64.b64encode(image_data).decode("utf-8")
        mime_type = self._get_image_mime_type(file_path)
        return f"data:{mime_type};base64,{encoded_data}"

    def _get_image_mime_type(self, file_path: str) -> str:
        """Get MIME type for image based on file extension."""
        file_path_lower = file_path.lower()

        if file_path_lower.endswith((".jpg", ".jpeg")):
            return "image/jpeg"
        if file_path_lower.endswith(".png"):
            return "image/png"
        if file_path_lower.endswith(".gif"):
            return "image/gif"
        if file_path_lower.endswith(".webp"):
            return "image/webp"
        return "image/jpeg"

    def build_enhanced_metadata(
        self, model_name: str | None = None, metadata: dict[str, Any] | None = None
    ) -> dict[str, Any]:
        """Build enhanced metadata combining telemetry, agent info, and custom metadata."""
        enhanced_metadata = {
            **self.telemetry.to_langfuse_config(),
            "agent_name": self.agent_name,
            **(metadata or {}),
        }

        if model_name:
            enhanced_metadata["model"] = model_name

        return enhanced_metadata

    def build_langchain_config(
        self, callback_handler=None, metadata: dict[str, Any] | None = None
    ) -> dict[str, Any]:
        """Build LangChain RunnableConfig for LangGraph agents."""
        config = {
            "run_name": self.telemetry.session_id,
            "configurable": {
                "thread_id": self.telemetry.session_id,
            },
            "metadata": self.build_enhanced_metadata(metadata=metadata),
        }

        if callback_handler:
            config["callbacks"] = [callback_handler]

        return config
