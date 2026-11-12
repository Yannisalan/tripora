"""Operator CLI for administrator management.

Run on the server (e.g. Render Shell) or locally against a database you
control:

    flask --app wsgi admin grant user@example.com
    flask --app wsgi admin reset-mfa user@example.com
    flask --app wsgi admin revoke user@example.com
    flask --app wsgi admin revoke-sessions user@example.com
    flask --app wsgi admin list

These commands never print or log secrets. Granting admin opens a 24-hour
window in which that user can enroll TOTP at /admin/login; after enrollment
only a TOTP code or a recovery code completes sign-in. There is deliberately
no HTTP endpoint that can grant or revoke the admin role.
"""

import click
from flask.cli import AppGroup

from config.database import db
from models.admin_security import AdminMfa
from models.user import ROLE_ADMIN, ROLE_USER, User
from services import admin_auth, db_context

admin_cli = AppGroup("admin", help="Manage Tripora administrators.")


def _user_or_fail(email):
    user = User.query.filter_by(email=str(email).strip().lower()).first()
    if user is None:
        raise click.ClickException("No account with that email.")
    return user


@admin_cli.command("grant")
@click.argument("email")
def grant(email):
    """Make an existing, verified, password account an administrator."""
    with db_context.scoped(auth_flow=True, admin_read=True):
        user = _user_or_fail(email)
        if not user.email_verified:
            raise click.ClickException("The account's email is not verified.")
        if not user.password_hash:
            raise click.ClickException(
                "Administrators need a password account (not social-only)."
            )
        user.role = ROLE_ADMIN
        admin_auth.revoke_sessions(user.id)
        admin_auth.open_enrollment(user.id)
        db.session.commit()
        admin_auth.audit("role_granted_cli", user.id)
        click.echo(
            "Granted admin to user {}. They must enroll TOTP at /admin/login "
            "within {} hours.".format(user.id, admin_auth.ENROLLMENT_WINDOW_HOURS)
        )


@admin_cli.command("reset-mfa")
@click.argument("email")
def reset_mfa(email):
    """Remove an admin's TOTP + recovery codes and reopen enrollment."""
    with db_context.scoped(auth_flow=True, admin_read=True):
        user = _user_or_fail(email)
        if user.role != ROLE_ADMIN:
            raise click.ClickException("That account is not an administrator.")
        admin_auth.revoke_sessions(user.id)
        admin_auth.open_enrollment(user.id)
        db.session.commit()
        admin_auth.audit("mfa_reset_cli", user.id)
        click.echo(
            "MFA reset for user {}. Enrollment open for {} hours.".format(
                user.id, admin_auth.ENROLLMENT_WINDOW_HOURS)
        )


@admin_cli.command("revoke")
@click.argument("email")
def revoke(email):
    """Remove the admin role, MFA and all admin sessions."""
    with db_context.scoped(auth_flow=True, admin_read=True):
        user = _user_or_fail(email)
        user.role = ROLE_USER
        admin_auth.revoke_sessions(user.id)
        AdminMfa.query.filter_by(user_id=user.id).delete(
            synchronize_session=False)
        db.session.commit()
        admin_auth.audit("role_revoked_cli", user.id)
        click.echo("Revoked admin from user {}.".format(user.id))


@admin_cli.command("revoke-sessions")
@click.argument("email")
def revoke_sessions(email):
    """End every admin session of an administrator."""
    with db_context.scoped(auth_flow=True, admin_read=True):
        user = _user_or_fail(email)
        admin_auth.revoke_sessions(user.id)
        db.session.commit()
        admin_auth.audit("sessions_revoked_cli", user.id)
        click.echo("Admin sessions revoked for user {}.".format(user.id))


@admin_cli.command("list")
def list_admins():
    """List administrators (id, email, MFA state)."""
    with db_context.scoped(auth_flow=True, admin_read=True):
        for user in User.query.filter_by(role=ROLE_ADMIN).order_by(User.id):
            mfa = db.session.get(AdminMfa, user.id)
            state = (
                "enrolled" if mfa is not None and mfa.enabled_at
                else "enrollment-open" if admin_auth.enrollment_open(mfa)
                else "no-mfa"
            )
            click.echo("{}\t{}\t{}".format(user.id, user.email, state))


def register_cli(app):
    if "admin" not in app.cli.commands:
        app.cli.add_command(admin_cli)
