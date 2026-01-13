"""Python Temporal Worker.

Registers Python activities and workflows on the 'palad_python' task queue.
"""

import asyncio
from concurrent.futures import ThreadPoolExecutor
from temporalio.client import Client
from temporalio.worker import Worker

from temporal.activities import (
    codebase_analyze_file,
    codebase_index_file_in_vector_db,
    codebase_generate_report_section,
    document_analyze_file,
    document_index_in_vector_db,
    image_analyze_file,
    image_index_in_vector_db,
    generate_domains,
    generate_features,
    generate_user_stories,
    generate_use_cases,
    generate_erd_diagram,
    generate_dataflow_diagram,
    model_list_get
)
from config import settings
from temporal.workflows import (
    AssetCodebaseWorkflow,
    AssetDocumentWorkflow,
    AssetImageWorkflow,
    AssetImageCollectionWorkflow,
    SpecificationProcessingWorkflow,
)

from core.logging import logger


async def main() -> None:
    """Start Python Temporal worker."""
    address = f"{settings.temporal.host}:{settings.temporal.port}"
    task_queue = settings.temporal.task_queues.python
    client = await Client.connect(address)

    activities = [
        codebase_analyze_file,
        codebase_index_file_in_vector_db,
        codebase_generate_report_section,
        document_analyze_file,
        document_index_in_vector_db,
        image_analyze_file,
        image_index_in_vector_db,
        generate_domains,
        generate_features,
        generate_user_stories,
        generate_use_cases,
        generate_erd_diagram,
        generate_dataflow_diagram,
        model_list_get
    ]

    workflows = [
        AssetCodebaseWorkflow,
        AssetDocumentWorkflow,
        AssetImageWorkflow,
        AssetImageCollectionWorkflow,
        SpecificationProcessingWorkflow,
    ]

    logger.info(
        f"Python worker - registered workflows: [{', '.join([wf.name() for wf in workflows])}]"
    )
    logger.info(
        f"Python worker - registered activities: [{', '.join([act.__name__ for act in activities])}]"
    )

    with ThreadPoolExecutor(max_workers=settings.temporal.max_workers) as executor:
        worker = Worker(
            client,
            task_queue=task_queue,
            activities=activities,
            workflows=workflows,
            activity_executor=executor,
        )

        logger.info("Python worker - listening for tasks")

        await worker.run()


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        logger.info("Worker stopped")
