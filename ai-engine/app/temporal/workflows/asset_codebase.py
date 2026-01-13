"""CodeBase asset processing workflow.

Flow:
1. Extract archive & create CodeBase + CodeReport (Ruby)
2. For each file (batched parallel):
   a. Analyze file with LLM (Python)
   b. Save analysis metadata (Ruby)
   c. Index in vector DB (Python)
3. For each report section (parallel):
   a. Generate section with LLM (Python)
   b. Save section (Ruby)
4. Finalize CodeReport (Ruby) - update status
"""

from temporalio import workflow
from temporal.workflows.base import BaseWorkflow
from temporalio.exceptions import ActivityError, FailureError, is_cancelled_exception
import asyncio
from typing import Iterator

from constants import Workflows, get_section_types
from workflows.helpers import (
    execute_activity,
    finalize_asset,
    fail_asset,
    EXTENDED_TIMEOUT,
)

# Batch size for file processing to avoid exceeding Temporal and PostgreSQL limits
# Each file creates 4 activities (load, analyze, save, index)
# 500 files = max 2000 concurrent activities per batch
FILE_PROCESSING_BATCH_SIZE = 500


def chunk_list(items: list, batch_size: int) -> Iterator[list]:
    """Split list into batches of specified size.

    Args:
        items: List to split into batches
        batch_size: Size of each batch

    Yields:
        Batches of items
    """
    for i in range(0, len(items), batch_size):
        yield items[i:i + batch_size]  # fmt: skip


@workflow.defn(name=Workflows.asset_codebase_processing.name)
class AssetCodebaseWorkflow(BaseWorkflow):
    """CodeBase asset processing workflow."""

    @workflow.run
    async def run(self, asset_id: int) -> dict:
        """Process CodeBase asset end-to-end.

        Args:
            asset_id: ID of the Asset (type: CODE)

        Returns:
            dict with processing results
        """

        async def extract_and_prepare() -> dict:
            return await execute_activity(
                Workflows.asset_codebase_processing.activities.codebase_extract_and_prepare,
                asset_id,
            )

        async def process_file(file_id: int, extraction: dict) -> dict:
            """Process single file: load → analyze → save → index."""
            try:
                # Load file content from storage (Ruby - handles S3/Shrine)
                file_data_key = await execute_activity(
                    Workflows.asset_codebase_processing.activities.codebase_load_file_content,
                    file_id,
                )

                # Analyze file with LLM (Python - uses content from Ruby)
                analysis_key = await execute_activity(
                    Workflows.asset_codebase_processing.activities.codebase_analyze_file,
                    {
                        "file_data_key": file_data_key,
                        "file_id": file_id,
                        "codebase_indexing_model": extraction["codebase_indexing_model"],
                        "moe_expert2_model": extraction.get("moe_expert2_model"),
                        "moe_expert3_model": extraction.get("moe_expert3_model"),
                    },
                )

                # Save analysis metadata to DB
                await execute_activity(
                    Workflows.asset_codebase_processing.activities.codebase_save_file_analysis,
                    {"file_id": file_id, "analysis_key": analysis_key},
                )

                # Index in vector DB (uses same file_data)
                await execute_activity(
                    Workflows.asset_codebase_processing.activities.codebase_index_file_in_vector_db,
                    {
                        "file_id": file_id,
                        "file_data_key": file_data_key,
                        "codebase_id": extraction["codebase_id"],
                        "workspace_id": extraction["workspace_id"],
                        "analysis_key": analysis_key,
                        "asset_id": asset_id,
                    },
                )

                return {"file_id": file_id, "ok": True}
            except ActivityError as e:
                workflow.logger.error(f"Error processing file {file_id}: {e}")
                if is_cancelled_exception(e):
                    raise e

        async def generate_section(section_type_def, extraction: dict) -> dict:
            try:
                # Initiate report section
                new_section = await execute_activity(
                    Workflows.asset_codebase_processing.activities.codebase_initiate_report_section,
                    {
                        "name": section_type_def.title,
                        "order": section_type_def.order,
                        "categories": section_type_def.categories,
                        "code_report_id": extraction["code_report_id"],
                        "codebase_id": extraction["codebase_id"],
                    },
                )

                # Generate section with LLM
                section_key = await execute_activity(
                    Workflows.asset_codebase_processing.activities.codebase_generate_report_section,
                    {
                        "prompt_name": section_type_def.prompt_name,
                        "categories": list(section_type_def.categories),
                        "codebase_reporting_model": extraction[
                            "codebase_reporting_model"
                        ],
                        "section_id": new_section["section_id"],
                        "files_data_key": new_section["files_data_key"],
                    },
                    timeout=EXTENDED_TIMEOUT,
                )

                # Save section to DB
                await execute_activity(
                    Workflows.asset_codebase_processing.activities.codebase_save_report_section,
                    {
                        "section_key": section_key,
                        "section_id": new_section["section_id"],
                    },
                )

                return new_section["section_id"]
            except ActivityError as e:
                await execute_activity(
                    Workflows.asset_codebase_processing.activities.codebase_fail_report_section,
                    new_section["section_id"],
                )
                if is_cancelled_exception(e):
                    raise e

        try:
            workflow.logger.info(f"Starting codebase processing: asset_id={asset_id}")

            # Step 1: Extract archive & create CodeBase + CodeReport
            extraction = await extract_and_prepare()
            file_ids = extraction["file_ids"]
            total_files = len(file_ids)
            workflow.logger.info(
                f"Processing {total_files} files, codebase={extraction['codebase_id']}, report={extraction['code_report_id']}"
            )

            # Step 2: Process files in batches to avoid exceeding Temporal and PostgreSQL limits
            # Each file creates 4 activities, so batch_size=500 gives max 2000 concurrent activities per batch
            processed_files = []
            if total_files > 0:
                total_batches = (
                    total_files + FILE_PROCESSING_BATCH_SIZE - 1
                ) // FILE_PROCESSING_BATCH_SIZE
                workflow.logger.info(
                    f"Processing {total_files} files in {total_batches} batches (batch size: {FILE_PROCESSING_BATCH_SIZE})"
                )

                for batch_num, batch_file_ids in enumerate(
                    chunk_list(file_ids, FILE_PROCESSING_BATCH_SIZE), 1
                ):
                    batch_size = len(batch_file_ids)
                    workflow.logger.info(
                        f"Processing batch {batch_num}/{total_batches} ({batch_size} files)"
                    )

                    # Process files in current batch in parallel
                    batch_results = await asyncio.gather(
                        *[process_file(fid, extraction) for fid in batch_file_ids]
                    )
                    processed_files.extend(batch_results)

                    workflow.logger.info(
                        f"Completed batch {batch_num}/{total_batches} ({batch_size} files processed)"
                    )

                workflow.logger.info(f"Processed {len(processed_files)} files total")
            else:
                workflow.logger.info("No files to process")

            # Step 3: Generate report sections in parallel
            generated_sections = await asyncio.gather(
                *[generate_section(st, extraction) for st in get_section_types()]
            )
            workflow.logger.info(
                f"Generated {len(generated_sections)} report sections in parallel"
            )

            # Step 4: Finalize - update statuses
            result = await finalize_asset(asset_id)
            workflow.logger.info(f"CodeBase processing completed for asset={asset_id}")

        except FailureError as e:
            workflow.logger.error(
                f"Error processing codebase for asset={asset_id}: {e}"
            )
            await fail_asset(asset_id)
            raise e

        return {
            "asset_id": asset_id,
            "codebase_id": extraction["codebase_id"],
            "code_report_id": extraction["code_report_id"],
            "processed_files": len(processed_files),
            "generated_sections": len(generated_sections),
            "ok": result["ok"],
        }
