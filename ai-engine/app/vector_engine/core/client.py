"""Vector database client with connection management."""

from core.logging import logger
from qdrant_client import QdrantClient
from qdrant_client.models import CollectionInfo, Distance, VectorParams

from config import settings

from .config import VectorCoreConfig
from .exceptions import VectorEngineError
from .retry import RetryConfig, with_retry


class VectorClient:
    """
    Unified client for vector database operations.
    Handles connection management and basic operations.
    """

    def __init__(self, config: VectorCoreConfig | None = None):
        """Initialize vector client with configuration."""
        self.config = config or VectorCoreConfig()
        self.client: QdrantClient | None = None
        self.logger = logger

    def connect(self) -> None:
        """Establish connection to vector database."""
        try:
            self.client = QdrantClient(
                host=settings.qdrant.host,
                port=settings.qdrant.port,
                timeout=self.config.connection_timeout,
            )

            # Test connection
            self.client.get_collections()
            self.logger.info("Successfully connected to vector database")

        except Exception as e:
            self.logger.error(f"Failed to connect to vector database: {e}")
            raise VectorEngineError(f"Vector database connection failed: {e}")

    def get_client(self) -> QdrantClient:
        """Get the Qdrant client, connecting if necessary."""
        if self.client is None:
            self.connect()
        return self.client

    @with_retry(
        RetryConfig(
            max_attempts=3, retryable_exceptions=(ConnectionError, TimeoutError)
        ),
        "create_collection",
    )
    def create_collection(
        self,
        collection_name: str,
        vector_size: int = 1536,  # text-embedding-3-small default
        distance: Distance = Distance.COSINE,
    ) -> None:
        """Create a new collection with retry logic."""
        client = self.get_client()

        try:
            client.create_collection(
                collection_name=collection_name,
                vectors_config=VectorParams(
                    size=vector_size,
                    distance=distance,
                ),
            )
            self.logger.info(f"Created collection: {collection_name}")

        except Exception as e:
            if "already exists" in str(e).lower():
                self.logger.debug(f"Collection {collection_name} already exists")
                return
            raise VectorEngineError(
                f"Failed to create collection {collection_name}: {e}"
            )

    @with_retry(
        RetryConfig(
            max_attempts=2, retryable_exceptions=(ConnectionError, TimeoutError)
        ),
        "collection_exists",
    )
    def collection_exists(self, collection_name: str) -> bool:
        """Check if collection exists."""
        client = self.get_client()

        try:
            collections = client.get_collections()
            return any(col.name == collection_name for col in collections.collections)

        except Exception as e:
            raise VectorEngineError(f"Failed to check collection existence: {e}")

    @with_retry(
        RetryConfig(
            max_attempts=2, retryable_exceptions=(ConnectionError, TimeoutError)
        ),
        "get_collection_info",
    )
    def get_collection_info(self, collection_name: str) -> CollectionInfo | None:
        """Get collection information."""
        client = self.get_client()

        try:
            return client.get_collection(collection_name)

        except Exception as e:
            if "not found" in str(e).lower():
                return None
            raise VectorEngineError(f"Failed to get collection info: {e}")

    @with_retry(
        RetryConfig(
            max_attempts=3, retryable_exceptions=(ConnectionError, TimeoutError)
        ),
        "delete_collection",
    )
    def delete_collection(self, collection_name: str) -> None:
        """Delete a collection."""
        client = self.get_client()

        try:
            client.delete_collection(collection_name)
            self.logger.info(f"Deleted collection: {collection_name}")

        except Exception as e:
            if "not found" in str(e).lower():
                self.logger.debug(f"Collection {collection_name} does not exist")
                return
            raise VectorEngineError(
                f"Failed to delete collection {collection_name}: {e}"
            )

    def get_collection_name(self, workspace_id: int) -> str:
        """Generate collection name for workspace."""
        return f"{self.config.collection_prefix}_{workspace_id}"

    def close(self) -> None:
        """Close the connection."""
        if self.client:
            try:
                self.client.close()
                self.client = None
                self.logger.info("Vector database connection closed")
            except Exception as e:
                self.logger.warning(f"Error closing connection: {e}")


def get_vector_client(config: VectorCoreConfig | None = None) -> VectorClient:
    """Get or create global vector client instance."""
    return VectorClient(config)
