"""Auth & User Management API routes.

POST /api/auth/register
POST /api/auth/login
POST /api/auth/logout
GET  /api/auth/me

GET    /api/admin/users          (admin)
GET    /api/admin/users/:id      (admin)
PATCH  /api/admin/users/:id      (admin)
DELETE /api/admin/users/:id      (admin)
GET    /api/admin/stats          (admin)
GET    /api/admin/history        (admin)
"""
from datetime import datetime, timezone
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Request, Query
from pydantic import BaseModel, EmailStr, Field
from sqlalchemy.orm import Session
from sqlalchemy import func, desc

from .database import get_db, User, ChatSession, ChatMessage, LoginAudit, utcnow
from .auth import (
    hash_password, verify_password, create_access_token,
    get_current_user, get_current_admin, log_login_event,
)

router = APIRouter()


# ── Schemas ──

class RegisterReq(BaseModel):
    email: str = Field(..., min_length=5)
    username: str = Field(..., min_length=3, max_length=50)
    full_name: str = Field(..., min_length=2)
    password: str = Field(..., min_length=6)
    department: Optional[str] = None

class LoginReq(BaseModel):
    username: str
    password: str

class UserOut(BaseModel):
    id: int
    email: str
    username: str
    full_name: str
    role: str
    is_active: bool
    department: Optional[str]
    created_at: datetime
    last_login: Optional[datetime]

    class Config:
        from_attributes = True

class UserUpdate(BaseModel):
    full_name: Optional[str] = None
    role: Optional[str] = None
    is_active: Optional[bool] = None
    department: Optional[str] = None


# ── Auth Endpoints ──

@router.post("/auth/register")
def register(req: RegisterReq, db: Session = Depends(get_db)):
    # Check duplicates
    if db.query(User).filter(User.email == req.email).first():
        raise HTTPException(400, "Email already registered")
    if db.query(User).filter(User.username == req.username).first():
        raise HTTPException(400, "Username already taken")

    # First user = admin
    user_count = db.query(func.count(User.id)).scalar()
    role = "admin" if user_count == 0 else "user"

    user = User(
        email=req.email,
        username=req.username,
        full_name=req.full_name,
        hashed_password=hash_password(req.password),
        role=role,
        department=req.department,
    )
    db.add(user)
    db.commit()
    db.refresh(user)

    token = create_access_token({"sub": str(user.id), "role": user.role})
    return {
        "token": token,
        "user": UserOut.model_validate(user).model_dump(),
        "message": f"Account created. Role: {role}",
    }


@router.post("/auth/login")
def login(req: LoginReq, request: Request, db: Session = Depends(get_db)):
    user = db.query(User).filter(User.username == req.username).first()
    if not user:
        raise HTTPException(401, "Invalid credentials")

    if not verify_password(req.password, user.hashed_password):
        log_login_event(db, user.id, "failed_login", request)
        raise HTTPException(401, "Invalid credentials")

    if not user.is_active:
        raise HTTPException(403, "Account is deactivated")

    # Update last_login
    user.last_login = utcnow()
    db.commit()
    db.refresh(user)

    log_login_event(db, user.id, "login", request)

    token = create_access_token({"sub": str(user.id), "role": user.role})
    return {
        "token": token,
        "user": UserOut.model_validate(user).model_dump(),
    }


@router.post("/auth/logout")
def logout(request: Request,
           user: User = Depends(get_current_user),
           db: Session = Depends(get_db)):
    log_login_event(db, user.id, "logout", request)
    return {"message": "Logged out"}


@router.get("/auth/me")
def me(user: User = Depends(get_current_user)):
    return UserOut.model_validate(user).model_dump()


# ── Admin: User Management ──

@router.get("/admin/users")
def list_users(
    skip: int = 0,
    limit: int = 50,
    search: Optional[str] = None,
    admin: User = Depends(get_current_admin),
    db: Session = Depends(get_db),
):
    q = db.query(User)
    if search:
        like = f"%{search}%"
        q = q.filter(
            (User.username.ilike(like)) |
            (User.full_name.ilike(like)) |
            (User.email.ilike(like))
        )
    total = q.count()
    users = q.order_by(desc(User.created_at)).offset(skip).limit(limit).all()

    result = []
    for u in users:
        ud = UserOut.model_validate(u).model_dump()
        # Add stats
        ud["session_count"] = db.query(func.count(ChatSession.id)).filter(
            ChatSession.user_id == u.id).scalar()
        ud["message_count"] = db.query(func.count(ChatMessage.id)).join(
            ChatSession).filter(ChatSession.user_id == u.id).scalar()
        result.append(ud)

    return {"users": result, "total": total}


@router.get("/admin/users/{user_id}")
def get_user(user_id: int,
             admin: User = Depends(get_current_admin),
             db: Session = Depends(get_db)):
    user = db.query(User).filter(User.id == user_id).first()
    if not user:
        raise HTTPException(404, "User not found")

    ud = UserOut.model_validate(user).model_dump()
    ud["session_count"] = db.query(func.count(ChatSession.id)).filter(
        ChatSession.user_id == user.id).scalar()
    ud["message_count"] = db.query(func.count(ChatMessage.id)).join(
        ChatSession).filter(ChatSession.user_id == user.id).scalar()

    # Recent sessions
    sessions = db.query(ChatSession).filter(
        ChatSession.user_id == user.id
    ).order_by(desc(ChatSession.updated_at)).limit(10).all()
    ud["recent_sessions"] = [
        {
            "session_id": s.session_id,
            "title": s.title,
            "message_count": s.message_count,
            "created_at": s.created_at.isoformat() if s.created_at else None,
            "updated_at": s.updated_at.isoformat() if s.updated_at else None,
        }
        for s in sessions
    ]

    # Login history
    logins = db.query(LoginAudit).filter(
        LoginAudit.user_id == user.id
    ).order_by(desc(LoginAudit.created_at)).limit(20).all()
    ud["login_history"] = [
        {
            "action": l.action,
            "ip_address": l.ip_address,
            "created_at": l.created_at.isoformat() if l.created_at else None,
        }
        for l in logins
    ]

    return ud


@router.patch("/admin/users/{user_id}")
def update_user(user_id: int, req: UserUpdate,
                admin: User = Depends(get_current_admin),
                db: Session = Depends(get_db)):
    user = db.query(User).filter(User.id == user_id).first()
    if not user:
        raise HTTPException(404, "User not found")

    if req.full_name is not None:
        user.full_name = req.full_name
    if req.role is not None:
        user.role = req.role
    if req.is_active is not None:
        user.is_active = req.is_active
    if req.department is not None:
        user.department = req.department

    db.commit()
    db.refresh(user)
    return UserOut.model_validate(user).model_dump()


@router.delete("/admin/users/{user_id}")
def delete_user(user_id: int,
                admin: User = Depends(get_current_admin),
                db: Session = Depends(get_db)):
    user = db.query(User).filter(User.id == user_id).first()
    if not user:
        raise HTTPException(404, "User not found")
    if user.id == admin.id:
        raise HTTPException(400, "Cannot delete yourself")

    db.delete(user)
    db.commit()
    return {"message": f"User {user.username} deleted"}


# ── Admin: Stats ──

@router.get("/admin/stats")
def admin_stats(admin: User = Depends(get_current_admin),
                db: Session = Depends(get_db)):
    total_users = db.query(func.count(User.id)).scalar()
    active_users = db.query(func.count(User.id)).filter(User.is_active == True).scalar()
    total_sessions = db.query(func.count(ChatSession.id)).scalar()
    total_messages = db.query(func.count(ChatMessage.id)).scalar()

    # Users active last 24h
    from datetime import timedelta
    cutoff = utcnow() - timedelta(hours=24)
    active_24h = db.query(func.count(func.distinct(LoginAudit.user_id))).filter(
        LoginAudit.created_at >= cutoff,
        LoginAudit.action == "login",
    ).scalar()

    # Messages per day (last 7 days)
    daily_msgs = db.query(
        func.date(ChatMessage.created_at).label("day"),
        func.count(ChatMessage.id).label("count"),
    ).group_by("day").order_by(desc("day")).limit(7).all()

    # Top users by messages
    top_users = db.query(
        User.username,
        User.full_name,
        func.count(ChatMessage.id).label("msg_count"),
    ).join(ChatSession, ChatSession.user_id == User.id
    ).join(ChatMessage, ChatMessage.session_id == ChatSession.id
    ).group_by(User.id).order_by(desc("msg_count")).limit(10).all()

    # Domain usage
    domain_usage = db.query(
        ChatMessage.domain,
        func.count(ChatMessage.id).label("count"),
    ).filter(ChatMessage.domain.isnot(None)
    ).group_by(ChatMessage.domain).order_by(desc("count")).limit(10).all()

    return {
        "total_users": total_users,
        "active_users": active_users,
        "active_24h": active_24h,
        "total_sessions": total_sessions,
        "total_messages": total_messages,
        "daily_messages": [{"day": str(d.day), "count": d.count} for d in daily_msgs],
        "top_users": [
            {"username": u.username, "full_name": u.full_name, "message_count": u.msg_count}
            for u in top_users
        ],
        "domain_usage": [
            {"domain": d.domain, "count": d.count}
            for d in domain_usage
        ],
    }


# ── Admin: Chat History ──

@router.get("/admin/history")
def admin_history(
    user_id: Optional[int] = None,
    session_id: Optional[str] = None,
    skip: int = 0,
    limit: int = 20,
    admin: User = Depends(get_current_admin),
    db: Session = Depends(get_db),
):
    """Browse chat history across all users."""
    if session_id:
        # Get specific session messages
        session = db.query(ChatSession).filter(
            ChatSession.session_id == session_id).first()
        if not session:
            raise HTTPException(404, "Session not found")

        messages = db.query(ChatMessage).filter(
            ChatMessage.session_id == session.id
        ).order_by(ChatMessage.created_at).all()

        user = db.query(User).filter(User.id == session.user_id).first()
        return {
            "session": {
                "session_id": session.session_id,
                "title": session.title,
                "user": user.username if user else "?",
                "user_full_name": user.full_name if user else "?",
                "created_at": session.created_at.isoformat() if session.created_at else None,
                "message_count": session.message_count,
            },
            "messages": [
                {
                    "id": m.id,
                    "role": m.role,
                    "content": m.content[:500] if m.content else "",
                    "domain": m.domain,
                    "sql_query": m.sql_query,
                    "row_count": m.row_count,
                    "latency_ms": m.latency_ms,
                    "created_at": m.created_at.isoformat() if m.created_at else None,
                }
                for m in messages
            ],
        }

    # List sessions
    q = db.query(ChatSession).join(User)
    if user_id:
        q = q.filter(ChatSession.user_id == user_id)

    total = q.count()
    sessions = q.order_by(desc(ChatSession.updated_at)).offset(skip).limit(limit).all()

    return {
        "sessions": [
            {
                "session_id": s.session_id,
                "title": s.title,
                "user": s.user.username,
                "user_full_name": s.user.full_name,
                "message_count": s.message_count,
                "created_at": s.created_at.isoformat() if s.created_at else None,
                "updated_at": s.updated_at.isoformat() if s.updated_at else None,
            }
            for s in sessions
        ],
        "total": total,
    }


# ── User: Chat History ──

@router.get("/chat/sessions")
def user_sessions(
    skip: int = 0,
    limit: int = 20,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """List user's own chat sessions."""
    total = db.query(func.count(ChatSession.id)).filter(
        ChatSession.user_id == user.id).scalar()
    sessions = db.query(ChatSession).filter(
        ChatSession.user_id == user.id
    ).order_by(desc(ChatSession.updated_at)).offset(skip).limit(limit).all()

    return {
        "sessions": [
            {
                "session_id": s.session_id,
                "title": s.title,
                "message_count": s.message_count,
                "created_at": s.created_at.isoformat() if s.created_at else None,
                "updated_at": s.updated_at.isoformat() if s.updated_at else None,
            }
            for s in sessions
        ],
        "total": total,
    }


@router.get("/chat/sessions/{session_id}")
def user_session_detail(
    session_id: str,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    """Get messages for user's own session."""
    session = db.query(ChatSession).filter(
        ChatSession.session_id == session_id,
        ChatSession.user_id == user.id,
    ).first()
    if not session:
        raise HTTPException(404, "Session not found")

    messages = db.query(ChatMessage).filter(
        ChatMessage.session_id == session.id
    ).order_by(ChatMessage.created_at).all()

    return {
        "session_id": session.session_id,
        "title": session.title,
        "messages": [
            {
                "id": m.id,
                "role": m.role,
                "content": m.content,
                "domain": m.domain,
                "created_at": m.created_at.isoformat() if m.created_at else None,
            }
            for m in messages
        ],
    }
