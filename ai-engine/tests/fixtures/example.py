"""User authentication service for managing login and session handling."""

import hashlib
import secrets
from datetime import datetime, timedelta

from models.session import UserSession
from models.user import User
from sqlalchemy.orm import Session


class AuthenticationService:
    """Handles user authentication and session management."""

    def __init__(self, db: Session):
        self.db = db
        self.session_timeout = timedelta(hours=24)

    def authenticate_user(self, email: str, password: str) -> User | None:
        """Authenticate user with email and password."""
        user = self.db.query(User).filter(User.email == email).first()
        if not user:
            return None

        if not self._verify_password(password, user.password_hash):
            return None

        # Update last login
        user.last_login = datetime.utcnow()
        self.db.commit()
        return user

    def create_session(self, user: User) -> str:
        """Create a new user session and return session token."""
        token = secrets.token_urlsafe(32)
        session = UserSession(
            token=token,
            user_id=user.id,
            expires_at=datetime.utcnow() + self.session_timeout,
            created_at=datetime.utcnow(),
        )

        self.db.add(session)
        self.db.commit()
        return token

    def validate_session(self, token: str) -> User | None:
        """Validate session token and return associated user."""
        session = (
            self.db.query(UserSession)
            .filter(
                UserSession.token == token, UserSession.expires_at > datetime.utcnow()
            )
            .first()
        )

        if not session:
            return None

        return session.user

    def _verify_password(self, password: str, password_hash: str) -> bool:
        """Verify password against stored hash."""
        return hashlib.sha256(password.encode()).hexdigest() == password_hash

    def _hash_password(self, password: str) -> str:
        """Hash password for storage."""
        return hashlib.sha256(password.encode()).hexdigest()
