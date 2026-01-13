"""Image processing activities - clean interface using services."""

from temporalio import activity
from llm import LLMFactory

@activity.defn
def model_list_get() -> str:
    client = LLMFactory.create_openrouter_llm()
    models = client.models.list()
    return models

