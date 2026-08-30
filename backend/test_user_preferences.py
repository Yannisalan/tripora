from models.user import User


def test_user_defaults_include_account_preferences():
    user = User(
        name="Jane Doe",
        email="jane@example.com",
        password_hash="hashed-password",
    )

    assert user.preferred_language == "en"
    assert user.preferred_currency == "USD"
