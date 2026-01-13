"""Image asset processing workflow.

Flow:
1. Load image content (Ruby)
2. Analyze image with UITranscriptionsAgent (Python) - placeholder
3. Save analysis metadata (Ruby)
4. Index in vector DB (Python)
5. Finalize Asset (Ruby) - update status
"""

from temporalio import workflow
from temporal.workflows.base import BaseWorkflow
from temporalio.exceptions import FailureError

from constants import Workflows
from workflows.helpers import execute_activity, finalize_asset, fail_asset


@workflow.defn(name=Workflows.asset_image_processing.name)
class AssetImageWorkflow(BaseWorkflow):
    @workflow.run
    async def run(self, asset_id: int) -> dict:
        async def load_content() -> dict:
            return await execute_activity(
                Workflows.asset_image_processing.activities.image_load_file_content,
                asset_id,
            )

        async def analyze_image(
            image_data_key: str,
            ui_vision_model: str,
            ui_critic_model: str,
            ui_summary_model: str,
        ) -> str:
            """Analyze image with UITranscriptionsAgent."""
            return await execute_activity(
                Workflows.asset_image_processing.activities.image_analyze_file,
                {
                    "image_data_key": image_data_key,
                    "asset_id": asset_id,
                    "ui_vision_model": ui_vision_model,
                    "ui_critic_model": ui_critic_model,
                    "ui_summary_model": ui_summary_model,
                },
            )

        async def save_analysis(analysis_key: str) -> dict:
            return await execute_activity(
                Workflows.asset_image_processing.activities.image_save_analysis,
                {"asset_id": asset_id, "analysis_key": analysis_key},
            )

        async def index_in_vector_db(
            workspace_id: int, image_data_key: str, analysis_key: str
        ) -> str:
            """Index image in vector database."""
            return await execute_activity(
                Workflows.asset_image_processing.activities.image_index_in_vector_db,
                {
                    "asset_id": asset_id,
                    "workspace_id": workspace_id,
                    "image_data_key": image_data_key,
                    "analysis_key": analysis_key,
                },
            )

        try:
            # Start workflow
            workflow.logger.info(f"Starting image processing: asset_id={asset_id}")

            # Step 1: Load image content from storage
            load_result = await load_content()
            image_data_key = load_result["image_data_key"]
            workspace_id = load_result["workspace_id"]
            ui_vision_model = load_result["ui_vision_model"]
            ui_critic_model = load_result["ui_critic_model"]
            ui_summary_model = load_result["ui_summary_model"]
            workflow.logger.info(f"Loaded image content for asset={asset_id}")

            # Step 2: Analyze image with UITranscriptionsAgent
            analysis_key = await analyze_image(
                image_data_key, ui_vision_model, ui_critic_model, ui_summary_model
            )
            workflow.logger.info(f"Analyzed image for asset={asset_id}")

            # Step 3: Save analysis to database
            await save_analysis(analysis_key)
            workflow.logger.info(f"Saved analysis for asset={asset_id}")

            # Step 4: Index in vector database
            document_id = await index_in_vector_db(
                workspace_id, image_data_key, analysis_key
            )
            workflow.logger.info(
                f"Indexed image in vector DB: document_id={document_id}"
            )

            # Step 5: Finalize - update statuses
            result = await finalize_asset(asset_id)
            workflow.logger.info(f"Image processing completed for asset={asset_id}")

            return {
                "asset_id": asset_id,
                "document_id": document_id,
                "ok": result["ok"],
            }

        except FailureError as e:
            workflow.logger.error(f"Error processing image for asset={asset_id}: {e}")
            await fail_asset(asset_id)
            raise e
