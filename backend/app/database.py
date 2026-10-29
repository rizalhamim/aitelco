"""Database models and session management.

SQLite-backed user management with SQLAlchemy ORM.
Tables: users, chat_sessions, chat_messages, login_audit, usage_log, app_downloads, app_clients
"""
import os
from datetime import datetime, timezone

from sqlalchemy import (
    create_engine, Column, Integer, String, Text, DateTime,
    Boolean, Float, ForeignKey, Index, func
)
from sqlalchemy.orm import declarative_base, sessionmaker, relationship

DB_PATH = os.environ.get(
    "TELCO_AI_DB",
    os.path.join(os.path.dirname(os.path.dirname(__file__)), "data", "telco_ai.db"),
)
DATABASE_URL = f"sqlite:///{DB_PATH}"

engine = create_engine(DATABASE_URL, connect_args={"check_same_thread": False})
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base = declarative_base()


def utcnow():
    return datetime.now(timezone.utc)


# ── Models ──

class User(Base):
    __tablename__ = "users"

    id = Column(Integer, primary_key=True, autoincrement=True)
    email = Column(String(255), unique=True, nullable=False, index=True)
    username = Column(String(100), unique=True, nullable=False, index=True)
    full_name = Column(String(255), nullable=False)
    hashed_password = Column(String(255), nullable=False)
    role = Column(String(20), default="user", nullable=False)  # user, admin
    is_active = Column(Boolean, default=True, nullable=False)
    department = Column(String(100), nullable=True)
    created_at = Column(DateTime, default=utcnow, nullable=False)
    updated_at = Column(DateTime, default=utcnow, onupdate=utcnow)
    last_login = Column(DateTime, nullable=True)
    login_count = Column(Integer, default=0, nullable=False)

    # Relationships
    chat_sessions = relationship("ChatSession", back_populates="user", cascade="all, delete-orphan")
    login_audits = relationship("LoginAudit", back_populates="user", cascade="all, delete-orphan")


class ChatSession(Base):
    __tablename__ = "chat_sessions"

    id = Column(Integer, primary_key=True, autoincrement=True)
    session_id = Column(String(64), unique=True, nullable=False, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False, index=True)
    title = Column(String(500), nullable=True)
    created_at = Column(DateTime, default=utcnow, nullable=False)
    updated_at = Column(DateTime, default=utcnow, onupdate=utcnow)
    is_archived = Column(Boolean, default=False)
    message_count = Column(Integer, default=0)

    # Relationships
    user = relationship("User", back_populates="chat_sessions")
    messages = relationship("ChatMessage", back_populates="session", cascade="all, delete-orphan",
                            order_by="ChatMessage.created_at")

    __table_args__ = (
        Index("ix_chat_sessions_user_updated", "user_id", "updated_at"),
    )


class ChatMessage(Base):
    __tablename__ = "chat_messages"

    id = Column(Integer, primary_key=True, autoincrement=True)
    session_id = Column(Integer, ForeignKey("chat_sessions.id"), nullable=False, index=True)
    role = Column(String(20), nullable=False)  # user, assistant
    content = Column(Text, nullable=False)
    domain = Column(String(50), nullable=True)
    sql_query = Column(Text, nullable=True)
    row_count = Column(Integer, nullable=True)
    latency_ms = Column(Integer, nullable=True)
    created_at = Column(DateTime, default=utcnow, nullable=False)
    metadata_json = Column(Text, nullable=True)  # Extra data as JSON

    # Relationships
    session = relationship("ChatSession", back_populates="messages")


class LoginAudit(Base):
    __tablename__ = "login_audit"

    id = Column(Integer, primary_key=True, autoincrement=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False, index=True)
    action = Column(String(20), nullable=False)  # login, logout, failed_login
    ip_address = Column(String(45), nullable=True)
    user_agent = Column(String(500), nullable=True)
    created_at = Column(DateTime, default=utcnow, nullable=False)

    user = relationship("User", back_populates="login_audits")


class UsageLog(Base):
    """General purpose usage/activity log for queries, exports, etc."""
    __tablename__ = "usage_log"

    id = Column(Integer, primary_key=True, autoincrement=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False, index=True)
    action = Column(String(50), nullable=False)  # login, logout, register, query, export
    domain = Column(String(50), nullable=True)
    detail = Column(Text, nullable=True)
    created_at = Column(DateTime, default=utcnow, nullable=False)



class LoginToken(Base):
    __tablename__ = "login_tokens"

    id = Column(Integer, primary_key=True, autoincrement=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False, index=True)
    code = Column(String(4), nullable=False)
    expires_at = Column(DateTime, nullable=False)
    used = Column(Boolean, default=False, nullable=False)
    created_at = Column(DateTime, default=utcnow, nullable=False)

class PasswordReset(Base):
    __tablename__ = "password_resets"

    id = Column(Integer, primary_key=True, autoincrement=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False, index=True)
    token = Column(String(128), unique=True, nullable=False, index=True)
    expires_at = Column(DateTime, nullable=False)
    used = Column(Boolean, default=False, nullable=False)
    created_at = Column(DateTime, default=utcnow, nullable=False)


class Notification(Base):
    __tablename__ = "notifications"

    id = Column(Integer, primary_key=True, autoincrement=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False, index=True)
    title = Column(String(255), nullable=False)
    message = Column(Text, nullable=False)
    kind = Column(String(30), default="info", nullable=False)  # info, success, warn, alert
    is_read = Column(Boolean, default=False, nullable=False)
    created_at = Column(DateTime, default=utcnow, nullable=False)


class AppDownload(Base):
    """One APK download (web Download page or the in-app updater)."""
    __tablename__ = "app_downloads"

    id = Column(Integer, primary_key=True, autoincrement=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=True, index=True)
    version_name = Column(String(32), nullable=True)
    version_code = Column(Integer, nullable=True)
    source = Column(String(20), nullable=False, default="unknown")  # web, in_app, unknown
    ip_address = Column(String(45), nullable=True)
    user_agent = Column(String(500), nullable=True)
    created_at = Column(DateTime, default=utcnow, nullable=False, index=True)


class AppClient(Base):
    """Last known app install per user + device, from the X-App-* request headers."""
    __tablename__ = "app_clients"

    id = Column(Integer, primary_key=True, autoincrement=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False, index=True)
    platform = Column(String(20), nullable=False)          # android, web
    device_model = Column(String(120), nullable=False, default="")
    os_version = Column(String(60), nullable=True)
    app_version = Column(String(32), nullable=True)
    app_build = Column(Integer, nullable=True)
    first_seen = Column(DateTime, default=utcnow, nullable=False)
    last_seen = Column(DateTime, default=utcnow, nullable=False, index=True)

    __table_args__ = (Index("ix_app_clients_user_device", "user_id", "platform", "device_model", unique=True),)


# ── Database Init ──

def init_db():
    """Create tables if they don't exist, and seed default admin user."""
    os.makedirs(os.path.dirname(DB_PATH), exist_ok=True)
    Base.metadata.create_all(bind=engine)

    # Auto-create default admin if no users exist
    db = SessionLocal()
    try:
        user_count = db.query(User).count()
        if user_count == 0:
            # First boot only. Never hardcode or reset the admin password here:
            # it used to be committed in this file and re-applied on every start.
            import secrets
            from passlib.context import CryptContext
            pwd_ctx = CryptContext(schemes=["bcrypt"], deprecated="auto")
            initial = os.environ.get("ADMIN_INITIAL_PASSWORD") or secrets.token_urlsafe(12)
            admin = User(
                username="admin",
                email="admin@ioh.co.id",
                hashed_password=pwd_ctx.hash(initial),
                full_name="Administrator",
                role="admin",
                is_active=True,
            )
            db.add(admin)
            db.commit()
            if os.environ.get("ADMIN_INITIAL_PASSWORD"):
                print("[init_db] Default admin user created (username: admin, password from ADMIN_INITIAL_PASSWORD)")
            else:
                print(f"[init_db] Default admin user created (username: admin, password: {initial}). Change it after first login.")
    finally:
        db.close()


def get_db():
    """FastAPI dependency for DB session."""
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
