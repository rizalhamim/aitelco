"""Auth & user management API routes."""
import secrets
import uuid
from datetime import datetime, timedelta, timezone

from fastapi import APIRouter, Depends, HTTPException, status, BackgroundTasks, Request
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session
from sqlalchemy import func

from .database import (
    get_db, User, ChatSession, ChatMessage, UsageLog, LoginAudit,
    PasswordReset, Notification, utcnow,
)
from .auth import (
    hash_password, verify_password,
    create_access_token, create_refresh_token, decode_token,
    get_current_user, require_admin, get_current_user_optional,
)
from . import email_service

router = APIRouter(prefix="/api/auth", tags=["auth"])
admin_router = APIRouter(prefix="/api/admin", tags=["admin"])


# ── Schemas ──

class RegisterReq(BaseModel):
    username: str = Field(min_length=3, max_length=64)
    email: str
    password: str = Field(min_length=6)
    full_name: str = ""


class LoginReq(BaseModel):
    username: str
    password: str

class VerifyTokenReq(BaseModel):
    username: str
    code: str

class TokenResp(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    user: dict


def _audit(db: Session, user: User, action: str, request: Request | None) -> None:
    """Login audit row for the admin Statistik page. Failure actions name the reason:
    failed_login (wrong password), failed_inactive, failed_token."""
    ip = ua = None
    if request is not None:
        fwd = request.headers.get("x-forwarded-for", "")
        ip = (fwd.split(",")[0].strip() or (request.client.host if request.client else None))
        ip = ip[:45] if ip else None
        ua = (request.headers.get("user-agent") or "")[:500] or None
    db.add(LoginAudit(user_id=user.id, action=action, ip_address=ip, user_agent=ua))
    db.commit()


@router.post("/login", response_model=TokenResp)
def login(req: LoginReq, request: Request, db: Session = Depends(get_db)):
    """Direct username+password login. Returns access+refresh tokens immediately."""
    user = db.query(User).filter(User.username == req.username).first()
    if not user or not verify_password(req.password, user.hashed_password):
        if user:
            _audit(db, user, "failed_login", request)
        raise HTTPException(401, "Invalid username or password")
    if not user.is_active:
        _audit(db, user, "failed_inactive", request)
        raise HTTPException(403, "Account is deactivated")

    user.last_login = utcnow()
    user.login_count = (user.login_count or 0) + 1
    db.add(UsageLog(user_id=user.id, action="login"))
    _audit(db, user, "login", request)

    access = create_access_token({"sub": user.username, "role": user.role})
    refresh = create_refresh_token({"sub": user.username})
    return TokenResp(
        access_token=access,
        refresh_token=refresh,
        user=_user_dict(user),
    )


@router.post("/login/request-token")
def request_login_token(req: LoginReq, bg: BackgroundTasks, db: Session = Depends(get_db)):
    user = db.query(User).filter(User.username == req.username).first()
    if not user or not verify_password(req.password, user.hashed_password):
        raise HTTPException(401, "Invalid username or password")
    if not user.is_active:
        raise HTTPException(403, "Account is deactivated")
    if not user.email or "@" not in user.email:
        raise HTTPException(400, "User email not set. Contact admin.")

    # Check if a token was generated recently (last 60s)
    from .database import LoginToken
    from datetime import datetime, timezone, timedelta
    recent_token = db.query(LoginToken).filter(
        LoginToken.user_id == user.id,
        LoginToken.created_at >= datetime.now(timezone.utc) - timedelta(seconds=60)
    ).first()
    
    if recent_token:
        # Calculate remaining seconds
        elapsed = (datetime.now(timezone.utc).replace(tzinfo=None) - recent_token.created_at).total_seconds()
        remaining = max(0, 60 - int(elapsed))
        raise HTTPException(429, f"Please wait {remaining} seconds before requesting a new token.")

    # Generate 4-digit code
    import random
    code = f"{random.randint(0, 9999):04d}"
    
    # Store token (valid for 5 mins)
    token_entry = LoginToken(
        user_id=user.id,
        code=code,
        expires_at=datetime.now(timezone.utc) + timedelta(minutes=5)
    )
    db.add(token_entry)
    db.commit()

    # Send email
    from . import email_service
    bg.add_task(email_service.send_login_token, user.email, user.full_name or user.username, code)
    
    # Mask email for privacy
    parts = user.email.split('@')
    masked_email = f"{parts[0][:2]}***@{parts[1]}" if len(parts[0]) > 2 else f"***@{parts[1]}"

    return {"ok": True, "message": f"Token sent to {masked_email}"}

@router.post("/login/verify", response_model=TokenResp)
def verify_login_token(req: VerifyTokenReq, request: Request, db: Session = Depends(get_db)):
    user = db.query(User).filter(User.username == req.username).first()
    if not user:
        raise HTTPException(401, "Invalid username")
        
    from .database import LoginToken
    from datetime import datetime, timezone
    
    token_entry = db.query(LoginToken).filter(
        LoginToken.user_id == user.id,
        LoginToken.code == req.code,
        LoginToken.used == False
    ).order_by(LoginToken.created_at.desc()).first()
    
    if not token_entry:
        _audit(db, user, "failed_token", request)
        raise HTTPException(401, "Invalid token")
        
    if token_entry.expires_at < datetime.now(timezone.utc).replace(tzinfo=None):
        _audit(db, user, "failed_token", request)
        raise HTTPException(401, "Token expired")

    token_entry.used = True
    user.last_login = utcnow()
    user.login_count += 1
    db.commit()

    db.add(UsageLog(user_id=user.id, action="login"))
    _audit(db, user, "login", request)

    access = create_access_token({"sub": user.username, "role": user.role})
    refresh = create_refresh_token({"sub": user.username})

    return TokenResp(
        access_token=access,
        refresh_token=refresh,
        user=_user_dict(user),
    )


@router.post("/refresh")
def refresh_token(body: dict, db: Session = Depends(get_db)):
    token = body.get("refresh_token", "")
    payload = decode_token(token)
    if not payload or payload.get("type") != "refresh":
        raise HTTPException(401, "Invalid refresh token")

    username = payload.get("sub")
    user = db.query(User).filter(User.username == username).first()
    if not user or not user.is_active:
        raise HTTPException(401, "User not found or inactive")

    access = create_access_token({"sub": user.username, "role": user.role})
    return {"access_token": access, "token_type": "bearer"}


@router.get("/me")
def get_me(user: User = Depends(get_current_user)):
    return _user_dict(user)



class ChangePasswordReq(BaseModel):
    old_password: str
    new_password: str = Field(min_length=6)

@router.put("/me/password")
def change_password(
    req: ChangePasswordReq,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    if not verify_password(req.old_password, user.hashed_password):
        raise HTTPException(400, "Old password is incorrect")
    user.hashed_password = hash_password(req.new_password)
    db.commit()
    return {"ok": True}


# ── Profile Update ──

class UpdateProfileReq(BaseModel):
    full_name: str | None = None
    email: str | None = None
    department: str | None = None


@router.put("/me/profile")
def update_profile(
    req: UpdateProfileReq,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    if req.email is not None:
        if not req.email or "@" not in req.email:
            raise HTTPException(400, "Valid email is required")
        existing = db.query(User).filter(User.email == req.email, User.id != user.id).first()
        if existing:
            raise HTTPException(400, "Email already used by another account")
        user.email = req.email
    if req.full_name is not None:
        user.full_name = req.full_name
    if req.department is not None:
        user.department = req.department
    db.commit()
    return _user_dict(user)


# ── Forgot / Reset Password ──

class ForgotPasswordReq(BaseModel):
    email: str


class ResetPasswordReq(BaseModel):
    token: str
    new_password: str = Field(min_length=6)


@router.post("/forgot-password")
def forgot_password(req: ForgotPasswordReq, bg: BackgroundTasks, db: Session = Depends(get_db)):
    user = db.query(User).filter(User.email == req.email).first()
    if not user or not user.is_active:
        return {"ok": True, "message": "If that email exists, a reset link has been sent."}

    token = secrets.token_urlsafe(48)
    reset = PasswordReset(
        user_id=user.id,
        token=token,
        expires_at=datetime.now(timezone.utc) + timedelta(minutes=30),
    )
    db.add(reset)
    db.commit()

    bg.add_task(email_service.send_reset_link, user.email, user.username, token)

    return {"ok": True, "message": "If that email exists, a reset link has been sent."}


@router.post("/reset-password")
def reset_password(req: ResetPasswordReq, db: Session = Depends(get_db)):
    reset = db.query(PasswordReset).filter(
        PasswordReset.token == req.token,
        PasswordReset.used == False,
    ).first()
    if not reset:
        raise HTTPException(400, "Invalid or expired reset token")
    if reset.expires_at < datetime.now(timezone.utc):
        raise HTTPException(400, "Reset token has expired")

    user = db.query(User).filter(User.id == reset.user_id).first()
    if not user:
        raise HTTPException(400, "User not found")

    user.hashed_password = hash_password(req.new_password)
    reset.used = True
    db.commit()

    return {"ok": True, "message": "Password has been reset successfully"}


# ── Email Summary ──

class SendSummaryReq(BaseModel):
    question: str
    answer: str
    domain: str | None = None
    sql: str | None = None
    row_count: int | None = None


@router.post("/me/send-summary")
def send_summary_email(
    req: SendSummaryReq,
    bg: BackgroundTasks,
    user: User = Depends(get_current_user),
):
    if not user.email or user.email.endswith("@ioh.co.id") and user.email.startswith(user.username + "@"):
        raise HTTPException(400, "Please update your email in profile settings first")

    bg.add_task(
        email_service.send_chat_summary,
        user.email, user.full_name or user.username,
        req.question, req.answer, req.domain, req.sql, req.row_count,
    )
    return {"ok": True, "message": f"Summary will be sent to {user.email}"}


# ── AI Executive Summary of the WHOLE chat (Analyst model + PDF email) ──

class ChatTurn(BaseModel):
    role: str
    content: str = ""
    domain: str | None = None
    row_count: int | None = None
    result: dict | None = None            # {columns, rows, row_count} for data answers
    profile_sections: list[dict] | None = None  # [{section_title, columns, rows, row_count}]


class SummarizeChatReq(BaseModel):
    messages: list[ChatTurn]
    language: str = "id"


@router.post("/me/summarize-chat")
def summarize_chat_email(
    req: SummarizeChatReq,
    user: User = Depends(get_current_user),
):
    """Summarize the entire on-screen chat (key points/findings/insights/numbers/
    action items) using the Analyst LLM, then email it with a branded PDF.
    Runs SYNCHRONOUSLY so the response confirms whether the email was actually sent."""
    if not user.email or "@" not in (user.email or "") or (
        user.email.endswith("@ioh.co.id") and user.email.startswith(user.username + "@")
    ):
        raise HTTPException(400, "Set email valid di Profile dulu sebelum mengirim summary.")

    full_turns = [m.model_dump() for m in req.messages]
    msgs = [m for m in full_turns if (m.get("content") or "").strip()]
    if not msgs and not any(m.get("result") or m.get("profile_sections") for m in full_turns):
        raise HTTPException(400, "Belum ada percakapan untuk diringkas.")

    from . import chat_summary
    try:
        # summarize the WHOLE chat WITH its data; AI centers on the last topic.
        summary = chat_summary.summarize_chat(full_turns, language=req.language)
    except Exception as e:
        import logging
        logging.getLogger("routes_auth").error(f"summarize failed: {e}")
        raise HTTPException(502, "Gagal membuat ringkasan (AI Analyst). Coba lagi.")

    # PDF/email present the AI summary only (no raw-history appendix).
    sent = email_service.send_executive_summary(
        user.email, user.full_name or user.username, summary)
    if not sent:
        raise HTTPException(502, f"Ringkasan dibuat tapi gagal mengirim email ke {user.email}.")
    return {"ok": True, "sent": True, "email": user.email,
            "message": f"Email summary berhasil terkirim ke {user.email}"}


# ── Notifications ──

@router.get("/me/notifications")
def get_notifications(
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
    unread_only: bool = False,
    limit: int = 30,
):
    q = db.query(Notification).filter(Notification.user_id == user.id)
    if unread_only:
        q = q.filter(Notification.is_read == False)
    items = q.order_by(Notification.created_at.desc()).limit(limit).all()
    unread_count = db.query(func.count(Notification.id)).filter(
        Notification.user_id == user.id, Notification.is_read == False,
    ).scalar() or 0
    return {
        "unread_count": unread_count,
        "notifications": [
            {
                "id": n.id,
                "title": n.title,
                "message": n.message,
                "kind": n.kind,
                "is_read": n.is_read,
                "created_at": n.created_at.isoformat() if n.created_at else None,
            }
            for n in items
        ],
    }


@router.put("/me/notifications/{notif_id}/read")
def mark_notification_read(
    notif_id: int,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    n = db.query(Notification).filter(
        Notification.id == notif_id, Notification.user_id == user.id,
    ).first()
    if not n:
        raise HTTPException(404, "Notification not found")
    n.is_read = True
    db.commit()
    return {"ok": True}


@router.put("/me/notifications/read-all")
def mark_all_notifications_read(
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    db.query(Notification).filter(
        Notification.user_id == user.id, Notification.is_read == False,
    ).update({"is_read": True})
    db.commit()
    return {"ok": True}


# ── Chat History Routes ──

history_router = APIRouter(prefix="/api/history", tags=["history"])


@history_router.get("/sessions")
def list_sessions(
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
    limit: int = 50,
    offset: int = 0,
):
    sessions = (
        db.query(ChatSession)
        .filter(ChatSession.user_id == user.id, ChatSession.is_archived == False)
        .order_by(ChatSession.updated_at.desc())
        .offset(offset).limit(limit)
        .all()
    )
    return [
        {
            "session_id": s.session_id,
            "title": s.title,
            "message_count": s.message_count,
            "created_at": s.created_at.isoformat() if s.created_at else None,
            "updated_at": s.updated_at.isoformat() if s.updated_at else None,
        }
        for s in sessions
    ]


@history_router.get("/sessions/{session_id}")
def get_session_messages(
    session_id: str,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    session = (
        db.query(ChatSession)
        .filter(ChatSession.session_id == session_id,
                ChatSession.user_id == user.id)
        .first()
    )
    if not session:
        raise HTTPException(404, "Session not found")

    messages = (
        db.query(ChatMessage)
        .filter(ChatMessage.session_id == session.id)
        .order_by(ChatMessage.created_at)
        .all()
    )
    return {
        "session_id": session.session_id,
        "title": session.title,
        "messages": [
            {
                "role": m.role,
                "content": m.content,
                "domain": m.domain,
                "sql_query": m.sql_query,
                "row_count": m.row_count,
                "latency_ms": m.latency_ms,
                "created_at": m.created_at.isoformat() if m.created_at else None,
            }
            for m in messages
        ],
    }


@history_router.delete("/sessions/{session_id}")
def archive_session(
    session_id: str,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    session = (
        db.query(ChatSession)
        .filter(ChatSession.session_id == session_id,
                ChatSession.user_id == user.id)
        .first()
    )
    if not session:
        raise HTTPException(404, "Session not found")
    session.is_archived = True
    db.commit()
    return {"ok": True}


# ── Admin Routes ──

class CreateUserReq(BaseModel):
    username: str = Field(min_length=3, max_length=64)
    email: str = ""
    password: str = Field(min_length=6)
    full_name: str = ""
    role: str = "user"


@admin_router.post("/users")
def create_user(
    req: CreateUserReq,
    bg: BackgroundTasks,
    admin: User = Depends(require_admin),
    db: Session = Depends(get_db),
):
    """Admin creates a new user."""
    if db.query(User).filter(User.username == req.username).first():
        raise HTTPException(400, "Username already taken")
    if req.email and db.query(User).filter(User.email == req.email).first():
        raise HTTPException(400, "Email already registered")

    user = User(
        username=req.username,
        email=req.email or f"{req.username}@ioh.co.id",
        hashed_password=hash_password(req.password),
        full_name=req.full_name,
        role=req.role if req.role in ("admin", "analyst", "data_user", "end_user") else "end_user",
        is_active=True,
    )
    db.add(user)
    db.commit()
    db.refresh(user)

    if req.email and "@" in req.email:
        bg.add_task(email_service.send_welcome, req.email, req.username, req.full_name)

    return _user_dict(user)


@admin_router.post("/notify")
def admin_send_notification(
    body: dict,
    bg: BackgroundTasks,
    admin: User = Depends(require_admin),
    db: Session = Depends(get_db),
):
    """Admin sends notification to a user or all users."""
    title = body.get("title", "Notification")
    message = body.get("message", "")
    kind = body.get("kind", "info")
    user_id = body.get("user_id")
    send_email = body.get("send_email", False)

    if not message:
        raise HTTPException(400, "Message is required")

    if user_id:
        targets = db.query(User).filter(User.id == user_id, User.is_active == True).all()
    else:
        targets = db.query(User).filter(User.is_active == True).all()

    count = 0
    for u in targets:
        db.add(Notification(user_id=u.id, title=title, message=message, kind=kind))
        count += 1
        if send_email and u.email and "@" in u.email:
            bg.add_task(email_service.send_notification, u.email, title, message)
    db.commit()

    return {"ok": True, "notified": count}


@admin_router.get("/users")
def list_users(
    admin: User = Depends(require_admin),
    db: Session = Depends(get_db),
):
    users = db.query(User).order_by(User.created_at.desc()).all()
    return [_user_dict(u) for u in users]


@admin_router.get("/users/{user_id}")
def get_user_detail(
    user_id: int,
    admin: User = Depends(require_admin),
    db: Session = Depends(get_db),
):
    user = db.query(User).filter(User.id == user_id).first()
    if not user:
        raise HTTPException(404, "User not found")

    # Session + message counts
    sessions = db.query(ChatSession).filter(ChatSession.user_id == user_id).all()
    total_messages = (
        db.query(func.count(ChatMessage.id))
        .join(ChatSession)
        .filter(ChatSession.user_id == user_id)
        .scalar() or 0
    )

    return {
        **_user_dict(user),
        "total_sessions": len(sessions),
        "total_messages": total_messages,
        "recent_sessions": [
            {
                "session_id": s.session_id,
                "title": s.title,
                "message_count": s.message_count,
                "updated_at": s.updated_at.isoformat() if s.updated_at else None,
            }
            for s in sorted(sessions, key=lambda x: x.updated_at or datetime.min,
                            reverse=True)[:10]
        ],
    }



class UpdateUserReq(BaseModel):
    is_active: bool | None = None
    role: str | None = None
    full_name: str | None = None
    email: str | None = None

@admin_router.put("/users/{user_id}")
def update_user(
    user_id: int,
    req: UpdateUserReq,
    admin: User = Depends(require_admin),
    db: Session = Depends(get_db),
):
    user = db.query(User).filter(User.id == user_id).first()
    if not user:
        raise HTTPException(404, "User not found")
    if req.full_name is not None:
        user.full_name = req.full_name
    if req.email is not None:
        user.email = req.email
    if req.role is not None:
        user.role = req.role
    if req.is_active is not None:
        user.is_active = req.is_active
    db.commit()
    return _user_dict(user)


@admin_router.delete("/users/{user_id}")
def delete_user(
    user_id: int,
    admin: User = Depends(require_admin),
    db: Session = Depends(get_db),
):
    user = db.query(User).filter(User.id == user_id).first()
    if not user:
        raise HTTPException(404, "User not found")
    if user.id == admin.id:
        raise HTTPException(400, "Cannot delete your own account")
    if user.role == "admin":
        admin_count = db.query(func.count(User.id)).filter(User.role == "admin").scalar() or 0
        if admin_count <= 1:
            raise HTTPException(400, "Cannot delete the last admin")
    db.delete(user)
    db.commit()
    return {"ok": True, "deleted_user": user.username}


@admin_router.get("/stats")
def admin_stats(
    admin: User = Depends(require_admin),
    db: Session = Depends(get_db),
):
    total_users = db.query(func.count(User.id)).scalar() or 0
    active_users = db.query(func.count(User.id)).filter(User.is_active == True).scalar() or 0
    total_sessions = db.query(func.count(ChatSession.id)).scalar() or 0
    total_messages = db.query(func.count(ChatMessage.id)).scalar() or 0

    # Today stats
    today = datetime.now(timezone.utc).date()
    today_logins = (
        db.query(func.count(UsageLog.id))
        .filter(UsageLog.action == "login",
                func.date(UsageLog.created_at) == today)
        .scalar() or 0
    )
    today_queries = (
        db.query(func.count(UsageLog.id))
        .filter(UsageLog.action == "query",
                func.date(UsageLog.created_at) == today)
        .scalar() or 0
    )

    # Recent registrations (last 7 days)
    from datetime import timedelta
    week_ago = datetime.now(timezone.utc) - timedelta(days=7)
    new_users_7d = (
        db.query(func.count(User.id))
        .filter(User.created_at >= week_ago)
        .scalar() or 0
    )

    # Top users by queries
    top_users = (
        db.query(
            User.username, User.full_name,
            func.count(UsageLog.id).label("query_count"),
        )
        .join(UsageLog, UsageLog.user_id == User.id)
        .filter(UsageLog.action == "query")
        .group_by(User.id)
        .order_by(func.count(UsageLog.id).desc())
        .limit(10)
        .all()
    )

    # Domain distribution
    domain_dist = (
        db.query(
            UsageLog.domain,
            func.count(UsageLog.id).label("count"),
        )
        .filter(UsageLog.action == "query", UsageLog.domain.isnot(None))
        .group_by(UsageLog.domain)
        .order_by(func.count(UsageLog.id).desc())
        .all()
    )

    # Daily activity (last 30 days)
    from datetime import timedelta as td
    days_back = 30
    daily_data = []
    for d in range(days_back - 1, -1, -1):
        day = (datetime.now(timezone.utc) - td(days=d)).date()
        logins = (
            db.query(func.count(UsageLog.id))
            .filter(UsageLog.action == "login", func.date(UsageLog.created_at) == day)
            .scalar() or 0
        )
        queries = (
            db.query(func.count(UsageLog.id))
            .filter(UsageLog.action == "query", func.date(UsageLog.created_at) == day)
            .scalar() or 0
        )
        daily_data.append({"date": day.isoformat(), "logins": logins, "queries": queries})

    return {
        "total_users": total_users,
        "active_users": active_users,
        "new_users_7d": new_users_7d,
        "total_sessions": total_sessions,
        "total_messages": total_messages,
        "today_logins": today_logins,
        "today_queries": today_queries,
        "top_users": [
            {"username": u[0], "full_name": u[1], "query_count": u[2]}
            for u in top_users
        ],
        "domain_distribution": [
            {"domain": d[0], "count": d[1]}
            for d in domain_dist
        ],
        "daily_activity": daily_data,
    }


@admin_router.get("/users/{user_id}/activity")
def user_activity(
    user_id: int,
    admin: User = Depends(require_admin),
    db: Session = Depends(get_db),
    days: int = 30,
):
    """Per-user daily activity chart + domain breakdown + Q&A logs."""
    from datetime import timedelta as td

    user = db.query(User).filter(User.id == user_id).first()
    if not user:
        raise HTTPException(404, "User not found")

    # Daily queries
    daily = []
    for d in range(days - 1, -1, -1):
        day = (datetime.now(timezone.utc) - td(days=d)).date()
        q = (
            db.query(func.count(UsageLog.id))
            .filter(UsageLog.user_id == user_id, UsageLog.action == "query",
                    func.date(UsageLog.created_at) == day)
            .scalar() or 0
        )
        daily.append({"date": day.isoformat(), "queries": q})

    # Domain breakdown
    domains = (
        db.query(UsageLog.domain, func.count(UsageLog.id).label("cnt"))
        .filter(UsageLog.user_id == user_id, UsageLog.action == "query",
                UsageLog.domain.isnot(None))
        .group_by(UsageLog.domain)
        .order_by(func.count(UsageLog.id).desc())
        .all()
    )

    # Q&A logs: get user messages paired with assistant responses
    sessions = db.query(ChatSession).filter(ChatSession.user_id == user_id).all()
    qa_pairs = []
    for sess in sorted(sessions, key=lambda s: s.updated_at or datetime.min, reverse=True)[:20]:
        msgs = (
            db.query(ChatMessage)
            .filter(ChatMessage.session_id == sess.id)
            .order_by(ChatMessage.created_at)
            .all()
        )
        i = 0
        while i < len(msgs):
            if msgs[i].role == "user":
                answer = msgs[i + 1] if i + 1 < len(msgs) and msgs[i + 1].role == "assistant" else None
                qa_pairs.append({
                    "session_id": sess.session_id,
                    "question": msgs[i].content[:500],
                    "answer": (answer.content[:800] if answer else None),
                    "domain": (answer.domain if answer else None),
                    "sql_query": (answer.sql_query if answer else None),
                    "row_count": (answer.row_count if answer else None),
                    "latency_ms": (answer.latency_ms if answer else None),
                    "asked_at": msgs[i].created_at.isoformat() if msgs[i].created_at else None,
                })
                i += 2
            else:
                i += 1
        if len(qa_pairs) >= 50:
            break

    total_queries = (
        db.query(func.count(UsageLog.id))
        .filter(UsageLog.user_id == user_id, UsageLog.action == "query")
        .scalar() or 0
    )
    avg_latency = (
        db.query(func.avg(ChatMessage.latency_ms))
        .join(ChatSession)
        .filter(ChatSession.user_id == user_id,
                ChatMessage.role == "assistant",
                ChatMessage.latency_ms.isnot(None))
        .scalar()
    )

    return {
        "user": _user_dict(user),
        "total_queries": total_queries,
        "avg_latency_ms": round(avg_latency) if avg_latency else None,
        "daily_activity": daily,
        "domain_breakdown": [{"domain": d[0], "count": d[1]} for d in domains],
        "qa_pairs": qa_pairs[:50],
    }


@admin_router.get("/history")
def admin_all_history(
    admin: User = Depends(require_admin),
    db: Session = Depends(get_db),
    limit: int = 50,
    offset: int = 0,
    user_id: int | None = None,
):
    q = (
        db.query(ChatSession, User.username, User.full_name)
        .join(User, ChatSession.user_id == User.id)
    )
    if user_id:
        q = q.filter(ChatSession.user_id == user_id)
    sessions = (
        q.order_by(ChatSession.updated_at.desc())
        .offset(offset).limit(limit)
        .all()
    )
    return [
        {
            "session_id": s.session_id,
            "title": s.title,
            "username": username,
            "full_name": full_name,
            "message_count": s.message_count,
            "created_at": s.created_at.isoformat() if s.created_at else None,
            "updated_at": s.updated_at.isoformat() if s.updated_at else None,
        }
        for s, username, full_name in sessions
    ]


# ── Helper ──

def _user_dict(u: User) -> dict:
    return {
        "id": u.id,
        "username": u.username,
        "email": u.email,
        "full_name": u.full_name,
        "role": u.role,
        "is_active": u.is_active,
        "created_at": u.created_at.isoformat() if u.created_at else None,
        "last_login": u.last_login.isoformat() if u.last_login else None,
        "login_count": u.login_count,
    }
