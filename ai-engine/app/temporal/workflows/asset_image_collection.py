"""Image Collection asset processing workflow.

Flow:
1. Extract archive & create ImageCollection + Items (Ruby)
2. For each image item (parallel):
   a. Load image content (Ruby)
   b. Analyze image with UITranscriptionsAgent (Python)
   c. Save analysis metadata (Ruby)
   d. Index in vector DB (Python) - with ui_image_id
3. Finalize Asset (Ruby)
"""

from temporalio import workflow
from temporal.workflows.base import BaseWorkflow
from temporalio.exceptions import ActivityError, FailureError
import asyncio

from constants import Workflows
from workflows.helpers import execute_activity, finalize_asset, fail_asset


@workflow.defn(name=Workflows.asset_image_collection_processing.name)
class AssetImageCollectionWorkflow(BaseWorkflow):
    @workflow.run
    async def run(self, asset_id: int) -> dict:
        async def extract_and_prepare() -> dict:
            return await execute_activity(
                Workflows.asset_image_collection_processing.activities.image_collection_extract_and_prepare,
                asset_id,
            )

        async def process_image(image_item_id: int, extraction: dict) -> dict:
            try:
                image_data_key = await execute_activity(
                    Workflows.asset_image_collection_processing.activities.image_collection_load_file_content,
                    image_item_id,
                )

                analysis_key = await execute_activity(
                    Workflows.asset_image_processing.activities.image_analyze_file,
                    {
                        "image_data_key": image_data_key,
                        "asset_id": asset_id,
                        "ui_vision_model": extraction["ui_vision_model"],
                        "ui_critic_model": extraction["ui_critic_model"],
                        "ui_summary_model": extraction["ui_summary_model"],
                        "image_collection_id": extraction["image_collection_id"],
                        "image_item_id": image_item_id,
                    },
                )

                # Save analysis metadata to DB
                await execute_activity(
                    Workflows.asset_image_collection_processing.activities.image_collection_save_analysis,
                    {"image_item_id": image_item_id, "analysis_key": analysis_key},
                )

                # Index in vector DB (with ui_image_id!) - reuse image_index_in_vector_db
                await execute_activity(
                    Workflows.asset_image_processing.activities.image_index_in_vector_db,
                    {
                        "asset_id": asset_id,
                        "workspace_id": extraction["workspace_id"],
                        "image_data_key": image_data_key,
                        "analysis_key": analysis_key,
                        "image_collection_id": extraction["image_collection_id"],
                        "image_item_id": image_item_id,
                    },
                )

                return {"image_item_id": image_item_id, "ok": True}
            except ActivityError as e:
                workflow.logger.error(f"Error processing image {image_item_id}: {e}")
                raise e

        try:
            # Start workflow
            workflow.logger.info(
                f"Starting image collection processing: asset_id={asset_id}"
            )

            # Step 1: Extract archive, create ImageCollection + Items
            extraction = await extract_and_prepare()
            workflow.logger.info(
                f"Extracted {len(extraction['image_ids'])} images, image_collection={extraction['image_collection_id']}"
            )

            # Step 2: Process all images in parallel
            processed_images = await asyncio.gather(
                *[
                    process_image(image_id, extraction)
                    for image_id in extraction["image_ids"]
                ]
            )
            workflow.logger.info(
                f"Processed {len(processed_images)} images in parallel"
            )

            # Step 3: Finalize - update statuses
            result = await finalize_asset(asset_id)
            workflow.logger.info(
                f"Image collection processing completed for asset={asset_id}"
            )

            return {
                "asset_id": asset_id,
                "image_collection_id": extraction["image_collection_id"],
                "processed_images": len(processed_images),
                "ok": result["ok"],
            }

        except FailureError as e:
            workflow.logger.error(
                f"Error processing image collection for asset={asset_id}: {e}"
            )
            await fail_asset(asset_id)
            raise e
