if __package__:
    from .models import User
else:
    from models import User

LOCAL_DEVICE_NAME = "local_device"


def get_or_create_profile(session):
    profile = (
        session.query(User)
        .filter(User.name == LOCAL_DEVICE_NAME)
        .order_by(User.created_at)
        .first()
    )
    if profile is None:
        profile = User(name=LOCAL_DEVICE_NAME)
        session.add(profile)
        session.flush()
    return profile
