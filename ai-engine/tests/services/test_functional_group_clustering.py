import numpy as np
import pytest

from services.specification.domain_generation.functional_group_clustering import (
    FunctionalGroupClusteringService,
    ClusteringConfig,
)
from services.specification.domain_generation.models import (
    ClusterSummary,
    DomainCluster,
)
from tests.factories.python_factories import FunctionalGroupFactory


class TestFunctionalGroupClusteringService:
    @pytest.fixture
    def sample_groups(self):
        return [
            FunctionalGroupFactory(
                full_path="app/models/user.py",
                confidence=0.9,
                name="User Management",
                business_domain_hint="User authentication and management",
                entities=["User", "Session", "Profile"],
                user_goal="Manage user accounts and sessions",
                operations=["create_user", "login", "logout"],
                business_rules=["Email must be unique"],
            ),
            FunctionalGroupFactory(
                full_path="app/models/auth.py",
                confidence=0.85,
                name="Authentication",
                business_domain_hint="User authentication and security",
                entities=["User", "Session", "Token"],
                user_goal="Authenticate users and manage sessions",
                operations=["authenticate", "refresh_token"],
                business_rules=["Password must be hashed"],
            ),
            FunctionalGroupFactory(
                full_path="app/models/payment.py",
                confidence=0.8,
                name="Payment Processing",
                business_domain_hint="Payment processing and billing",
                entities=["Payment", "Invoice", "Transaction"],
                user_goal="Process payments and generate invoices",
                operations=["process_payment", "refund"],
                business_rules=["Payment must be verified"],
            ),
        ]

    @pytest.fixture
    def clustering_service(self):
        return FunctionalGroupClusteringService()

    @pytest.fixture
    def mock_embeddings_for_two_stage_clustering(self):
        def generate_embeddings_side_effect(texts, model):
            call_count = getattr(generate_embeddings_side_effect, "call_count", 0)
            generate_embeddings_side_effect.call_count = call_count + 1

            if generate_embeddings_side_effect.call_count == 1:
                return [
                    [1.0, 0.0, 0.0],
                    [0.9, 0.1, 0.0],
                    [0.0, 0.0, 1.0],
                ]
            else:
                return [
                    [float(i) * 0.5 + 0.1, float(i) * 0.3, float(i) * 0.2]
                    for i in range(len(texts))
                ]

        generate_embeddings_side_effect.call_count = 0
        return generate_embeddings_side_effect

    def test_embed_groups(self, clustering_service, sample_groups, mocker):
        mock_embedding_service = mocker.patch.object(
            clustering_service, "_embedding_service"
        )
        mock_embedding_service.generate_embeddings.return_value = [
            [0.1, 0.2, 0.3],
            [0.4, 0.5, 0.6],
            [0.7, 0.8, 0.9],
        ]

        vectors = clustering_service._embed_groups(sample_groups)

        assert len(vectors) == 3
        assert mock_embedding_service.generate_embeddings.called
        call_args = mock_embedding_service.generate_embeddings.call_args
        texts = call_args[0][0]
        assert len(texts) == 3
        assert "User authentication and management" in texts[0]
        assert "Manage user accounts and sessions" in texts[0]

    def test_cluster_vectors(self, clustering_service):
        vectors = [
            [0.1, 0.2, 0.3],
            [0.11, 0.21, 0.31],
            [0.9, 0.8, 0.7],
        ]

        labels = clustering_service._cluster_vectors(vectors)

        assert len(labels) == 3
        assert labels[0] == labels[1] or labels[0] != labels[2]

    def test_cluster_empty_groups(self, clustering_service):
        clusters = clustering_service.cluster([])
        assert clusters == {}

    def test_cluster_groups(self, clustering_service, sample_groups, mocker):
        mock_embedding_service = mocker.patch.object(
            clustering_service, "_embedding_service"
        )
        mock_embedding_service.generate_embeddings.return_value = [
            [0.1, 0.2, 0.3],
            [0.11, 0.21, 0.31],
            [0.9, 0.8, 0.7],
        ]

        clusters = clustering_service.cluster(sample_groups)

        assert len(clusters) >= 1
        total_groups = sum(len(groups) for groups in clusters.values())
        assert total_groups == len(sample_groups)

    def test_detect_outliers_small_cluster(self, clustering_service, sample_groups):
        clusters = {1: sample_groups[:2]}

        outliers = clustering_service.detect_outliers(clusters)

        assert len(outliers) == 0

    def test_detect_outliers_with_dissimilar_group(
        self, clustering_service, sample_groups
    ):
        clusters = {1: sample_groups}

        outliers = clustering_service.detect_outliers(clusters, jaccard_threshold=0.3)

        assert 1 in outliers
        assert len(outliers[1]) >= 1

    def test_cluster_domains_empty_clusters(self, clustering_service):
        domain_clusters = clustering_service.cluster_domains({})
        assert domain_clusters == []

    def test_cluster_domains(self, clustering_service, sample_groups, mocker):
        clusters = {
            1: sample_groups[:2],
            2: [sample_groups[2]],
        }

        mock_embedding_service = mocker.patch.object(
            clustering_service, "_embedding_service"
        )
        mock_embedding_service.generate_embeddings.return_value = [
            [0.1, 0.2, 0.3],
            [0.9, 0.8, 0.7],
        ]

        domain_clusters = clustering_service.cluster_domains(clusters)

        assert len(domain_clusters) >= 1
        assert all(hasattr(dc, "cluster_id") for dc in domain_clusters)
        assert all(hasattr(dc, "groups") for dc in domain_clusters)
        assert all(hasattr(dc, "status") for dc in domain_clusters)

    def test_process_domain_clusters_integration(
        self,
        clustering_service,
        sample_groups,
        mock_embeddings_for_two_stage_clustering,
        mocker,
    ):
        mock_embedding_service = mocker.patch.object(
            clustering_service, "_embedding_service"
        )
        mock_embedding_service.generate_embeddings.side_effect = (
            mock_embeddings_for_two_stage_clustering
        )

        domain_clusters = clustering_service.process_domain_clusters(sample_groups)

        assert len(domain_clusters) >= 1
        assert all(dc.status in ("main", "edge", "drop") for dc in domain_clusters)
        all_groups_in_clusters = []
        for dc in domain_clusters:
            all_groups_in_clusters.extend(dc.groups)
        assert len(all_groups_in_clusters) == len(sample_groups)

    def test_clustering_config_defaults(self):
        config = ClusteringConfig()

        assert config.distance_threshold == 0.3
        assert config.metric == "cosine"
        assert config.linkage == "average"
        assert config.embedding_model == "text-embedding-3-small"
        assert config.outlier_jaccard_threshold == 0.2
        assert config.domain_distance_threshold == 0.45
        assert config.target_min_domains == 10
        assert config.target_max_domains == 40
        assert config.domain_iteration_limit == 5
        assert config.domain_threshold_growth == 1.2
        assert config.domain_threshold_decay == 0.85

    def test_clustering_config_custom_values(self):
        config = ClusteringConfig(
            distance_threshold=0.5,
            metric="euclidean",
            linkage="complete",
            embedding_model="custom-model",
            outlier_jaccard_threshold=0.3,
            domain_distance_threshold=0.6,
            target_min_domains=5,
            target_max_domains=25,
            domain_iteration_limit=3,
            domain_threshold_growth=1.5,
            domain_threshold_decay=0.7,
        )

        assert config.distance_threshold == 0.5
        assert config.metric == "euclidean"
        assert config.linkage == "complete"
        assert config.embedding_model == "custom-model"
        assert config.outlier_jaccard_threshold == 0.3
        assert config.domain_distance_threshold == 0.6
        assert config.target_min_domains == 5
        assert config.target_max_domains == 25
        assert config.domain_iteration_limit == 3
        assert config.domain_threshold_growth == 1.5
        assert config.domain_threshold_decay == 0.7

    def test_custom_config_in_service(
        self, sample_groups, mock_embeddings_for_two_stage_clustering, mocker
    ):
        custom_config = ClusteringConfig(
            distance_threshold=0.5, domain_distance_threshold=0.6
        )
        service = FunctionalGroupClusteringService(config=custom_config)

        mock_embedding_service = mocker.patch.object(service, "_embedding_service")
        mock_embedding_service.generate_embeddings.side_effect = (
            mock_embeddings_for_two_stage_clustering
        )

        domain_clusters = service.process_domain_clusters(
            sample_groups, domain_clustering_threshold=0.7
        )

        assert domain_clusters is not None

    def test_adaptive_domain_clustering_caps_results(self, mocker):
        config = ClusteringConfig(
            target_min_domains=1,
            target_max_domains=2,
            domain_iteration_limit=1,
        )
        service = FunctionalGroupClusteringService(config=config)
        clusters = {idx: [FunctionalGroupFactory()] for idx in range(3)}
        summaries = [
            ClusterSummary(
                cluster_id=idx,
                groups=clusters[idx],
                hints={"hint"},
                entities={"Entity"},
                text_for_embedding=f"text-{idx}",
            )
            for idx in clusters
        ]
        vectors_array = np.array([[0.1, 0.2], [0.2, 0.3], [0.3, 0.4]])
        excessive_clusters = [
            DomainCluster(
                cluster_id=idx,
                groups=clusters[idx],
                avg_confidence=0.9 - idx * 0.1,
                status="main",
            )
            for idx in clusters
        ]

        mocker.patch.object(
            service,
            "_execute_domain_clustering",
            return_value=excessive_clusters,
        )

        result = service._adaptive_domain_clustering(
            clusters=clusters,
            summaries=summaries,
            vectors_array=vectors_array,
            base_threshold=0.4,
        )

        assert len(result) == 2
        assert result[0].avg_confidence >= result[1].avg_confidence

    def test_adaptive_domain_clustering_adjusts_threshold(self, sample_groups, mocker):
        config = ClusteringConfig(
            target_min_domains=2,
            target_max_domains=3,
            domain_iteration_limit=3,
        )
        service = FunctionalGroupClusteringService(config=config)
        clusters = {idx: [sample_groups[0]] for idx in range(2)}
        summaries = [
            ClusterSummary(
                cluster_id=idx,
                groups=clusters[idx],
                hints={"hint"},
                entities={"Entity"},
                text_for_embedding=f"text-{idx}",
            )
            for idx in clusters
        ]
        vectors_array = np.array([[0.1, 0.2], [0.2, 0.3]])

        first_batch = [
            DomainCluster(
                cluster_id=idx,
                groups=clusters[0],
                avg_confidence=0.9,
                status="main",
            )
            for idx in range(5)
        ]
        second_batch = [
            DomainCluster(
                cluster_id=idx,
                groups=clusters[0],
                avg_confidence=0.85,
                status="main",
            )
            for idx in range(2)
        ]

        mock_execute = mocker.patch.object(
            service,
            "_execute_domain_clustering",
            side_effect=[first_batch, second_batch],
        )

        base_threshold = 0.5
        result = service._adaptive_domain_clustering(
            clusters=clusters,
            summaries=summaries,
            vectors_array=vectors_array,
            base_threshold=base_threshold,
        )

        assert len(result) == 2
        assert mock_execute.call_count == 2
        _, first_kwargs = mock_execute.call_args_list[0]
        _, second_kwargs = mock_execute.call_args_list[1]
        assert first_kwargs["threshold"] == pytest.approx(base_threshold)
        assert second_kwargs["threshold"] == pytest.approx(
            base_threshold * config.domain_threshold_growth
        )

    def test_adaptive_domain_clustering_handles_small_dataset(self, mocker):
        config = ClusteringConfig(
            target_min_domains=10,
            target_max_domains=40,
            domain_iteration_limit=3,
        )
        service = FunctionalGroupClusteringService(config=config)
        clusters = {idx: [FunctionalGroupFactory()] for idx in range(3)}
        summaries = [
            ClusterSummary(
                cluster_id=idx,
                groups=clusters[idx],
                hints={"hint"},
                entities={"Entity"},
                text_for_embedding=f"text-{idx}",
            )
            for idx in clusters
        ]
        vectors_array = np.array([[0.1, 0.2], [0.2, 0.3], [0.3, 0.4]])
        small_result = [
            DomainCluster(
                cluster_id=idx,
                groups=clusters[idx],
                avg_confidence=0.8,
                status="main",
            )
            for idx in clusters
        ]

        mock_execute = mocker.patch.object(
            service,
            "_execute_domain_clustering",
            return_value=small_result,
        )

        base_threshold = 0.4
        result = service._adaptive_domain_clustering(
            clusters=clusters,
            summaries=summaries,
            vectors_array=vectors_array,
            base_threshold=base_threshold,
        )

        assert result == small_result
        assert mock_execute.call_count == 1
        _, kwargs = mock_execute.call_args
        assert kwargs["threshold"] == pytest.approx(base_threshold)
