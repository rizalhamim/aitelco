"""Notifications for the Android background check (WorkManager, every 15 minutes).

GET /api/notify/pending?after=<id>   unread notifications newer than <id> that should be
                                     shown as system notifications (push=True), oldest first

There is no push transport (FCM) yet: the app polls this cheap endpoint in the background
and shows what it returns, so the 06.00 Brief Pagi and new tasks reach the lock screen.
"""
from __future__ import annotations

from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session

from .auth import get_current_user
from .database import Notification, User, get_db

router = APIRouter(prefix="/api/notify", tags=["notify"])


@router.get("/pending")
def pending(after: int = Query(0, ge=0), user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    rows = (db.query(Notification)
            .filter(Notification.user_id == user.id, Notification.id > after, Notification.is_read.is_(False), Notification.push.is_(True))
            .order_by(Notification.id).limit(10).all())
    last = db.query(Notification.id).filter(Notification.user_id == user.id).order_by(Notification.id.desc()).first()
    return {"last_id": last[0] if last else 0,
            "items": [{"id": n.id, "title": n.title, "message": n.message, "kind": n.kind, "link": n.link,
                       "created_at": n.created_at.isoformat() if n.created_at else None} for n in rows]}
