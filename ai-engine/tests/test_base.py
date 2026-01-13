import pytest

from tests.factories import (
    DomainsBuilder,
    RubySpecificationContextBuilder,
    RubyDomainContextBuilder,
    FeaturesBuilder,
    RubyFeatureContextBuilder,
    UserStoriesBuilder,
    RubyUserStoryContextBuilder,
    UseCasesBuilder,
    DomainClustersBuilder,
)
from tests.test_helpers import PayloadHelper


class TestClient:
    def __init__(self):
        self.domains = DomainsBuilder()
        self.features = FeaturesBuilder()
        self.user_stories = UserStoriesBuilder()
        self.use_cases = UseCasesBuilder()
        self.domain_clusters = DomainClustersBuilder()


class RubyTestClient:
    def __init__(self):
        self.specification_context = RubySpecificationContextBuilder()
        self.domain_context = RubyDomainContextBuilder()
        self.feature_context = RubyFeatureContextBuilder()
        self.user_story_context = RubyUserStoryContextBuilder()


@pytest.mark.usefixtures("mock_redis")
class TestBase:
    @pytest.fixture(autouse=True)
    def setup(self, test_client: TestClient, ruby_test_client: RubyTestClient):
        self.client = test_client
        self.ruby_client = ruby_test_client
        self.payload_service = PayloadHelper()
