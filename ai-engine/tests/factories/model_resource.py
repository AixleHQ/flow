from typing import Any

from .ruby_factories import (
    SpecificationContextDataFactory,
    DomainContextFactory,
    FeatureContextFactory,
    UserStoryContextFactory,
)
from .python_factories import (
    DomainFactory,
    FeatureItemFactory,
    UserStoryItemFactory,
    UseCaseItemFactory,
    DomainClusterFactory,
)


class RubySpecificationContextBuilder:
    @staticmethod
    def create(version_id: int = 1, workspace_id: int = 1, **kwargs) -> dict:
        return SpecificationContextDataFactory.build(
            version_id=version_id, workspace_id=workspace_id, **kwargs
        )


class DomainsBuilder:
    def create(self, **kwargs) -> Any:
        return DomainFactory.build(**kwargs)

    def create_batch(self, size: int, **kwargs) -> list[Any]:
        return DomainFactory.build_batch(size, **kwargs)


class RubyDomainContextBuilder:
    @staticmethod
    def create(**kwargs) -> dict:
        filtered_kwargs = {k: v for k, v in kwargs.items() if v is not None}
        return DomainContextFactory.build(**filtered_kwargs)


class FeaturesBuilder:
    def create(self, **kwargs) -> Any:
        return FeatureItemFactory.build(**kwargs)

    def create_batch(self, size: int, **kwargs) -> list[Any]:
        return FeatureItemFactory.build_batch(size, **kwargs)


class RubyFeatureContextBuilder:
    @staticmethod
    def create(**kwargs) -> dict:
        filtered_kwargs = {k: v for k, v in kwargs.items() if v is not None}
        return FeatureContextFactory.build(**filtered_kwargs)


class UserStoriesBuilder:
    def create(self, **kwargs) -> Any:
        return UserStoryItemFactory.build(**kwargs)

    def create_batch(self, size: int, **kwargs) -> list[Any]:
        return UserStoryItemFactory.build_batch(size, **kwargs)


class RubyUserStoryContextBuilder:
    @staticmethod
    def create(**kwargs) -> dict:
        filtered_kwargs = {k: v for k, v in kwargs.items() if v is not None}
        return UserStoryContextFactory.build(**filtered_kwargs)


class UseCasesBuilder:
    def create(self, **kwargs) -> Any:
        return UseCaseItemFactory.build(**kwargs)

    def create_batch(self, size: int, **kwargs) -> list[Any]:
        return UseCaseItemFactory.build_batch(size, **kwargs)


class DomainClustersBuilder:
    def create(self, **kwargs) -> Any:
        return DomainClusterFactory.build(**kwargs)

    def create_batch(self, size: int, **kwargs) -> list[Any]:
        return DomainClusterFactory.build_batch(size, **kwargs)
