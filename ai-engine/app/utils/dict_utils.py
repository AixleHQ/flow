from typing import Iterable, Mapping, TypeVar

K = TypeVar("K")
V = TypeVar("V")


def dict_slice(
    d: Mapping[K, V], keys: Iterable[K], *, strict: bool = False
) -> dict[K, V]:
    """Analog of Ruby Hash#slice. strict=True -> KeyError if the key is missing."""
    if strict:
        return {k: d[k] for k in keys}  # raises KeyError if absent
    ks = set(keys)
    return {k: d[k] for k in ks & d.keys()}  # lenient: takes only existing ones


def dict_except(d: Mapping[K, V], keys: Iterable[K]) -> dict[K, V]:
    """Analog of Ruby Hash#except."""
    drop = set(keys)
    return {k: v for k, v in d.items() if k not in drop}
