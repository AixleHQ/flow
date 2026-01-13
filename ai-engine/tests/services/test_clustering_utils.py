import pytest

from services.specification.domain_generation.clustering_utils import ClusteringUtils
from services.specification.domain_generation.models import (
    ClusterSummary,
)
from tests.factories.python_factories import (
    FunctionalGroupFactory,
    DomainClusterFactory,
)


class TestClusteringUtils:
    @pytest.fixture
    def user_group(self):
        return FunctionalGroupFactory(
            full_path="app/models/user.py",
            confidence=0.9,
            name="User Management",
            business_domain_hint="Authentication",
            entities=["User"],
            user_goal="Manage",
        )

    @pytest.fixture
    def auth_group(self):
        return FunctionalGroupFactory(
            full_path="app/models/auth.py",
            confidence=0.9,
            name="Authentication",
            business_domain_hint="Authentication",
            entities=["User"],
            user_goal="Auth",
        )

    @pytest.fixture
    def payment_group(self):
        return FunctionalGroupFactory(
            full_path="app/models/payment.py",
            confidence=0.9,
            name="Payment",
            business_domain_hint="Billing",
            entities=["Payment"],
            user_goal="Process payments",
        )

    def test_jaccard_similarity_identical_sets(self):
        set_a = {"user", "profile", "account"}
        set_b = {"user", "profile", "account"}

        similarity = ClusteringUtils.jaccard_similarity(set_a, set_b)

        assert similarity == 1.0

    def test_jaccard_similarity_disjoint_sets(self):
        set_a = {"user", "profile"}
        set_b = {"payment", "billing"}

        similarity = ClusteringUtils.jaccard_similarity(set_a, set_b)

        assert similarity == 0.0

    def test_jaccard_similarity_partial_overlap(self):
        set_a = {"user", "profile", "account"}
        set_b = {"user", "profile", "settings"}

        similarity = ClusteringUtils.jaccard_similarity(set_a, set_b)

        assert similarity == 0.5

    def test_jaccard_similarity_empty_sets(self):
        set_a = set()
        set_b = set()

        similarity = ClusteringUtils.jaccard_similarity(set_a, set_b)

        assert similarity == 0.0

    def test_calculate_average_jaccard_with_similar_groups(self):
        group = FunctionalGroupFactory(entities=["User", "Session", "Profile"])
        other_groups = [
            FunctionalGroupFactory(entities=["User", "Session", "Token"]),
            FunctionalGroupFactory(entities=["User", "Profile", "Settings"]),
        ]

        avg_jaccard = ClusteringUtils.calculate_average_jaccard(group, other_groups)

        assert avg_jaccard == 0.5

    def test_calculate_average_jaccard_empty_list(self, user_group):
        avg_jaccard = ClusteringUtils.calculate_average_jaccard(user_group, [])

        assert avg_jaccard == 0.0

    def test_create_cluster_summary(self):
        groups = [
            FunctionalGroupFactory(
                confidence=0.8,
                business_domain_hint="Authentication",
                entities=["User", "Session"],
                user_goal="Manage user accounts",
            ),
            FunctionalGroupFactory(
                confidence=0.9,
                business_domain_hint="Authentication",
                entities=["User", "Token"],
                user_goal="Authenticate users",
            ),
        ]

        summary = ClusteringUtils.create_cluster_summary(cluster_id=1, groups=groups)

        assert isinstance(summary, ClusterSummary)
        assert summary.cluster_id == 1
        assert len(summary.groups) == 2
        assert "Authentication" in summary.hints
        assert "User" in summary.entities
        assert "Session" in summary.entities
        assert "Token" in summary.entities
        assert "Manage user accounts" in summary.text_for_embedding
        assert "Authenticate users" in summary.text_for_embedding

    def test_calculate_avg_confidence(self):
        groups = [
            FunctionalGroupFactory(confidence=0.8),
            FunctionalGroupFactory(confidence=0.6),
        ]

        avg_conf = ClusteringUtils.calculate_avg_confidence(groups)

        assert avg_conf == 0.7

    def test_calculate_avg_confidence_empty_list(self):
        avg_conf = ClusteringUtils.calculate_avg_confidence([])
        assert avg_conf == 0.0

    def test_determine_status_main(self, user_group, auth_group):
        groups = [user_group, auth_group]

        status = ClusteringUtils.determine_status(groups, avg_confidence=0.9)

        assert status == "main"

    def test_determine_status_edge(self, user_group):
        groups = [user_group]

        status = ClusteringUtils.determine_status(groups, avg_confidence=0.9)

        assert status == "edge"

    def test_determine_status_drop(self):
        groups = [FunctionalGroupFactory(confidence=0.5)]

        status = ClusteringUtils.determine_status(groups, avg_confidence=0.5)

        assert status == "drop"

    def test_create_domain_clusters(self, user_group, auth_group, payment_group):
        clusters = {
            1: [user_group, auth_group],
            2: [payment_group],
        }

        domain_clusters = ClusteringUtils.create_domain_clusters(clusters)

        assert len(domain_clusters) == 2
        assert domain_clusters[0].status == "main"
        assert domain_clusters[1].status == "edge"

    def test_prepare_groups_for_llm_main_cluster(self, user_group):
        domain_cluster = DomainClusterFactory(
            groups=[user_group],
            avg_confidence=0.9,
            status="main",
        )

        llm_payload = ClusteringUtils.prepare_groups_for_llm(domain_cluster)

        assert len(llm_payload) == 1
        assert llm_payload[0]["name"] == user_group.name
        assert llm_payload[0]["business_domain_hint"] == user_group.business_domain_hint
        assert llm_payload[0]["entities"] == user_group.entities
        assert llm_payload[0]["user_goal"] == user_group.user_goal

    def test_prepare_groups_for_llm_drop_cluster(self):
        domain_cluster = DomainClusterFactory(
            groups=[FunctionalGroupFactory(confidence=0.5)],
            avg_confidence=0.5,
            status="drop",
        )

        llm_payload = ClusteringUtils.prepare_groups_for_llm(domain_cluster)

        assert llm_payload == []

    def test_prepare_groups_for_llm_handles_none_business_rules(self):
        domain_cluster = DomainClusterFactory(
            groups=[FunctionalGroupFactory(business_rules=None)],
            avg_confidence=0.9,
            status="main",
        )

        llm_payload = ClusteringUtils.prepare_groups_for_llm(domain_cluster)

        assert len(llm_payload) == 1
        assert llm_payload[0]["business_rules"] == []
