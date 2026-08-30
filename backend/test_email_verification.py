from models.user import User


def test_user_email_verification_defaults_are_disabled():
    user = User(
        name="Jane Doe",
        email="jane@example.com",
        password_hash="hashed-password",
    )

    assert user.email_verified is False
    assert user.verification_token is not None
