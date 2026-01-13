"""Document asset processing workflow.

Flow:
1. Load document content (Ruby)
2. Analyze document with LLM (Python)
3. Save analysis metadata (Ruby)
4. Index in vector DB (Python)
5. Finalize Asset (Ruby) - update status
"""

from datetime import timedelta

from temporalio import workflow
from temporal.workflows.base import BaseWorkflow
from temporalio.exceptions import FailureError

from constants import Workflows
from workflows.helpers import execute_activity, finalize_asset, fail_asset


DOCUMENT_INDEXING_TIMEOUT = timedelta(minutes=20)


@workflow.defn(name=Workflows.asset_document_processing.name)
class AssetDocumentWorkflow(BaseWorkflow):
    """Document asset processing workflow."""

    @workflow.run
    async def run(self, asset_id: int) -> dict:
        """Process Document asset end-to-end.

        Args:
            asset_id: ID of the Asset (type: DOCUMENT)

        Returns:
            dict with processing results
        """

        async def load_content() -> dict:
            """Load document content from storage."""
            return await execute_activity(
                Workflows.asset_document_processing.activities.document_load_file_content,
                asset_id,
            )

        async def analyze_document(
            document_data_key: str, document_analysis_model: str
        ) -> str:
            """Analyze document with LLM."""
            return await execute_activity(
                Workflows.asset_document_processing.activities.document_analyze_file,
                {
                    "document_data_key": document_data_key,
                    "asset_id": asset_id,
                    "document_analysis_model": document_analysis_model,
                },
            )

        async def save_analysis(analysis_key: str) -> dict:
            """Save analysis results to database."""
            return await execute_activity(
                Workflows.asset_document_processing.activities.document_save_analysis,
                {"asset_id": asset_id, "analysis_key": analysis_key},
            )

        async def index_in_vector_db(workspace_id: int, analysis_key: str) -> str:
            """Index document in vector database."""
            return await execute_activity(
                Workflows.asset_document_processing.activities.document_index_in_vector_db,
                {
                    "asset_id": asset_id,
                    "workspace_id": workspace_id,
                    "analysis_key": analysis_key,
                },
                timeout=DOCUMENT_INDEXING_TIMEOUT,
            )

        # Note: Using shared helpers from workflows.helpers

        try:
            # Start workflow
            workflow.logger.info(f"Starting document processing: asset_id={asset_id}")

            # Step 1: Load document content from storage
            load_result = await load_content()
            document_data_key = load_result["document_data_key"]
            workspace_id = load_result["workspace_id"]
            document_analysis_model = load_result["document_analysis_model"]
            workflow.logger.info(f"Loaded document content for asset={asset_id}")

            # Step 2: Analyze document with LLM
            analysis_key = await analyze_document(
                document_data_key, document_analysis_model
            )
            workflow.logger.info(f"Analyzed document for asset={asset_id}")

            # Step 3: Save analysis to database
            await save_analysis(analysis_key)
            workflow.logger.info(f"Saved analysis for asset={asset_id}")

            # Step 4: Index in vector database
            document_id = await index_in_vector_db(workspace_id, analysis_key)
            workflow.logger.info(
                f"Indexed document in vector DB: document_id={document_id}"
            )

            # Step 5: Finalize - update statuses
            result = await finalize_asset(asset_id)
            workflow.logger.info(f"Document processing completed for asset={asset_id}")

            return {
                "asset_id": asset_id,
                "document_id": document_id,
                "ok": result["ok"],
            }

        except FailureError as e:
            workflow.logger.error(
                f"Error processing document for asset={asset_id}: {e}"
            )
            await fail_asset(asset_id)
            raise e
