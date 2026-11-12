from datetime import datetime

from config.database import db


# ============================================================
# USER REFRESH TOKEN MODEL
# ============================================================
#
# Long-lived, rotating refresh tokens that let a signed-in user obtain
# new short-lived access tokens without re-entering credentials. Only the
# SHA-256 hash of the raw token is ever stored, so a database leak does not
# expose usable tokens.
#
# Rotation + reuse detection:
#   - Every issued token belongs to a ``family_id`` (one family per login).
#   - On refresh the presented token is marked ``revoked_at`` and a new token
#     is minted in the same family (``replaced_by_hash`` points at it).
#   - Presenting an already-revoked token (a replay of a rotated token) is
#     treated as theft: the whole family is revoked at once.
#
# This table is intentionally NOT covered by Row-Level Security: the refresh
# endpoint runs before any access token exists, so there is no
# ``request.jwt.claims.sub`` GUC to key a policy on (the same reason the
# ``users`` table is only RLS-enabled without FORCE). All lookups go through
# the token hash, which is unguessable.
# ============================================================

class UserRefreshToken(db.Model):
    __tablename__ = "user_refresh_tokens"

    # ========================================================
    # PRIMARY KEY
    # ========================================================

    id = db.Column(
        db.Integer,
        primary_key=True,
    )

    # ========================================================
    # OWNER
    # ========================================================

    user_id = db.Column(
        db.Integer,
        db.ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )

    # ========================================================
    # TOKEN
    # ========================================================
    # ``token_hash`` is the SHA-256 hex digest of the raw token. It is the
    # only lookup key and never leaves the server.
    # --------------------------------------------------------

    token_hash = db.Column(
        db.String(64),
        unique=True,
        nullable=False,
        index=True,
    )

    # Groups every token descended from one login so a stolen/rotated token
    # replay can revoke the entire chain.
    family_id = db.Column(
        db.String(32),
        nullable=False,
        index=True,
    )

    # Hash of the token that replaced this one during rotation (if any).
    replaced_by_hash = db.Column(
        db.String(64),
        nullable=True,
    )

    # ========================================================
    # LIFECYCLE
    # ========================================================

    created_at = db.Column(
        db.DateTime,
        default=datetime.utcnow,
        nullable=False,
    )

    expires_at = db.Column(
        db.DateTime,
        nullable=False,
        index=True,
    )

    last_used_at = db.Column(
        db.DateTime,
        nullable=True,
    )

    revoked_at = db.Column(
        db.DateTime,
        nullable=True,
    )

    # ========================================================
    # CLIENT HINT (non-identifying; for diagnostics only)
    # ========================================================

    user_agent = db.Column(
        db.String(255),
        nullable=True,
    )

    @property
    def is_active(self):
        """True while the token is neither revoked nor expired."""
        return (
            self.revoked_at is None
            and self.expires_at is not None
            and self.expires_at > datetime.utcnow()
        )
