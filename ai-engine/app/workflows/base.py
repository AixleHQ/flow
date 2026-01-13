"""Base workflow class with auto-naming."""

from temporalio import workflow


class BaseWorkflow:
    """Base class for all workflows with auto-naming.

    Automatically generates workflow name from class name:
    - AssetCodebaseProcessingWorkflow -> asset_codebase_processing

    Usage:
        @workflow.defn
        class MyWorkflow(BaseWorkflow):
            @workflow.run
            async def run(self, input):
                ...

    To override name:
        @workflow.defn(name="custom_name")
        class MyWorkflow(BaseWorkflow):
            ...
    """

    @classmethod
    def workflow_name(cls) -> str:
        """Get workflow name from class name.

        Returns:
            Workflow name in snake_case
        """
        # Get class name without namespace
        class_name = cls.__name__

        # Remove 'Workflow' suffix if present
        if class_name.endswith("Workflow"):
            class_name = class_name[:-8]  # Remove 'Workflow'

        # Convert PascalCase to snake_case
        import re

        # Insert underscore before capitals
        snake = re.sub("(.)([A-Z][a-z]+)", r"\1_\2", class_name)
        snake = re.sub("([a-z0-9])([A-Z])", r"\1_\2", snake)

        return snake.lower()

    @classmethod
    def get_name(cls) -> str:
        """Alias for workflow_name for consistency."""
        return cls.workflow_name()


def auto_name_workflow(workflow_class):
    """Decorator to auto-name workflow from class name.
    """
    name = workflow_class.workflow_name()
    return workflow.defn(name=name)(workflow_class)
