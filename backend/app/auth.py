"""Authentication & authorization utilities.

JWT token management, password hashing, and FastAPI dependencies.
"""
import logging
import os
from datetime import datetime, timedelta, timezone
from typing import Optional

from fastapi import Depends, HTTPException, status, Request
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from jose import JWTError, jwt
from passlib.context import CryptContext
from sqlalchemy.orm import Session

from .database import get_db, User, LoginAudit, UsageLog, utcnow

# ── Config ──
_DEFAULT_SECRET = "telco-ai-secret-key-change-in-production-2024"
SECRET_KEY = os.environ.get("JWT_SECRET_KEY", _DEFAULT_SECRET)
if SECRET_KEY == _DEFAULT_SECRET:
    # The default key is public (it lives in git), so anyone could forge tokens.
    # Refuse to start in production; only warn in dev so local setups keep working.
    if os.environ.get("APP_ENV", "").lower() == "production":
        raise RuntimeError("JWT_SECRET_KEY must be set when APP_ENV=production")
    logging.getLogger(__name__).warning(
        "JWT_SECRET_KEY not set; using the public default key (dev only)")
ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_MINUTES = int(os.environ.get("JWT_EXPIRE_MINUTES", "480"))  # 8 hours

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")
security = HTTPBearer(auto_error=False)


# ── Password ──

def hash_password(password: str) -> str:
    return pwd_context.hash(password)


def verify_password(plain: str, hashed: str) -> bool:
    return pwd_context.verify(plain, hashed)


# ── JWT ──

def create_access_token(data: dict, expires_delta: Optional[timedelta] = None) -> str:
    to_encode = data.copy()
    expire = datetime.now(timezone.utc) + (expires_delta or timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES))
    to_encode.update({"exp": expire, "type": "access"})
    return jwt.encode(to_encode, SECRET_KEY, algorithm=ALGORITHM)


def create_refresh_token(data: dict) -> str:
    to_encode = data.copy()
    expire = datetime.now(timezone.utc) + timedelta(days=30)
    to_encode.update({"exp": expire, "type": "refresh"})
    return jwt.encode(to_encode, SECRET_KEY, algorithm=ALGORITHM)


def decode_token(token: str) -> dict:
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        return payload
    except JWTError:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token invalid or expired",
        )


# ── FastAPI Dependencies ──

async def get_current_user(
    credentials: Optional[HTTPAuthorizationCredentials] = Depends(security),
    db: Session = Depends(get_db),
) -> User:
    """Extract and validate user from JWT token."""
    if not credentials:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Not authenticated",
            headers={"WWW-Authenticate": "Bearer"},
        )

    payload = decode_token(credentials.credentials)
    sub = payload.get("sub")
    if sub is None:
        raise HTTPException(status_code=401, detail="Invalid token payload")

    # Tokens are issued with sub=username (see create_access_token). Resolve by
    # username FIRST — never assume a numeric sub is a user id, because numeric
    # usernames (e.g. "90086171") would otherwise be looked up as a PK that no
    # user owns, yielding a false 401. Fall back to PK only if no username match.
    user = db.query(User).filter(User.username == str(sub)).first()
    if not user:
        try:
            user = db.query(User).filter(User.id == int(sub)).first()
        except (ValueError, TypeError):
            user = None

    if not user or not user.is_active:
        raise HTTPException(status_code=401, detail="User not found or inactive")

    return user


async def get_current_admin(user: User = Depends(get_current_user)) -> User:
    """Require admin role."""
    if user.role != "admin":
        raise HTTPException(status_code=403, detail="Admin access required")
    return user

# Aliases for backward compatibility
require_admin = get_current_admin
get_current_user_optional = None  # defined below


async def get_optional_user(
    credentials: Optional[HTTPAuthorizationCredentials] = Depends(security),
    db: Session = Depends(get_db),
) -> Optional[User]:
    """Return user if authenticated, None otherwise."""
    if not credentials:
        return None
    try:
        payload = decode_token(credentials.credentials)
        sub = payload.get("sub")
        if sub:
            user = db.query(User).filter(
                User.username == str(sub), User.is_active == True).first()
            if not user:
                try:
                    user = db.query(User).filter(
                        User.id == int(sub), User.is_active == True).first()
                except (ValueError, TypeError):
                    user = None
            return user
    except Exception:
        pass
    return None

# Set the alias now that get_optional_user is defined
get_current_user_optional = get_optional_user


# ── Audit Helper ──

def log_login_event(db: Session, user_id: int, action: str,
                    request: Optional[Request] = None):
    """Record login/logout/failed events."""
    ip = None
    ua = None
    if request:
        ip = request.client.host if request.client else None
        ua = request.headers.get("user-agent", "")[:500]

    audit = LoginAudit(
        user_id=user_id,
        action=action,
        ip_address=ip,
        user_agent=ua,
    )
    db.add(audit)
    db.commit()
