class TokenizerStub:
    def __init__(self, tokens_per_character: float = 0.25) -> None:
        self.tokens_per_character = tokens_per_character

    def encode(self, text: str, disallowed_special: tuple[str, ...] = ()) -> list[int]:
        token_count = max(1, int(len(text) * self.tokens_per_character))
        return list(range(token_count))
