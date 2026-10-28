from pathlib import Path

from sqlalchemy import URL, create_engine, event
from sqlalchemy.orm import DeclarativeBase, sessionmaker

if __package__:
    from .config import DATABASE_PATH
else:
    from config import DATABASE_PATH


class Base(DeclarativeBase):
    pass


database_path = Path(DATABASE_PATH)
database_path.parent.mkdir(parents=True, exist_ok=True)

engine = create_engine(
    URL.create("sqlite", database=str(database_path)),
    connect_args={"check_same_thread": False},
)
SessionLocal = sessionmaker(bind=engine, autoflush=False, autocommit=False)


@event.listens_for(engine, "connect")
def _enable_sqlite_foreign_keys(connection, _connection_record):
    cursor = connection.cursor()
    cursor.execute("PRAGMA foreign_keys=ON")
    cursor.close()


def initialize_database():
    if __package__:
        from . import models  # noqa: F401
    else:
        import models  # noqa: F401

    Base.metadata.create_all(bind=engine)
