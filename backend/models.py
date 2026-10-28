from datetime import datetime, timezone
from uuid import uuid4

from sqlalchemy import Boolean, Float, ForeignKey, Integer, Text
from sqlalchemy.orm import mapped_column

if __package__:
    from .database import Base
else:
    from database import Base


def _utc_now_text():
    return datetime.now(timezone.utc).isoformat()


class User(Base):
    __tablename__ = "users"

    id = mapped_column(Text, primary_key=True, default=lambda: str(uuid4()))
    name = mapped_column(Text, nullable=False)
    created_at = mapped_column(Text, nullable=False, default=_utc_now_text)


class Contact(Base):
    __tablename__ = "contacts"

    id = mapped_column(Integer, primary_key=True, autoincrement=True)
    user_id = mapped_column(Text, ForeignKey("users.id"), nullable=False)
    name = mapped_column(Text, nullable=False)
    email = mapped_column(Text, nullable=False)
    relation = mapped_column(Text, nullable=True)


class ModelVersion(Base):
    __tablename__ = "model_versions"

    model_version_id = mapped_column(Text, primary_key=True)
    model_type = mapped_column(Text, nullable=False)
    file_path = mapped_column(Text, nullable=False)
    file_hash = mapped_column(Text, nullable=True)
    trained_on_dataset_version = mapped_column(Text, nullable=True)
    hyperparameters = mapped_column(Text, nullable=True)
    validation_metrics = mapped_column(Text, nullable=True)
    production_threshold_used = mapped_column(Float, nullable=True)
    status = mapped_column(Text, nullable=False)
    created_at = mapped_column(Text, nullable=False, default=_utc_now_text)
    reviewed_by = mapped_column(Text, nullable=True)
    reviewed_at = mapped_column(Text, nullable=True)
    notes = mapped_column(Text, nullable=True)


class PersonalCheckin(Base):
    __tablename__ = "personal_checkins"

    id = mapped_column(Integer, primary_key=True, autoincrement=True)
    user_id = mapped_column(Text, ForeignKey("users.id"), nullable=False)
    timestamp = mapped_column(Text, nullable=False)
    answers = mapped_column(Text, nullable=False)
    model_version_id = mapped_column(
        Text, ForeignKey("model_versions.model_version_id"), nullable=True
    )
    probability = mapped_column(Float, nullable=True)
    elevated_risk = mapped_column(Boolean, nullable=True)
    top_factors = mapped_column(Text, nullable=True)
    used_defaults_for = mapped_column(Text, nullable=True)


class FamilyAlert(Base):
    __tablename__ = "family_alerts"

    id = mapped_column(Integer, primary_key=True, autoincrement=True)
    checkin_id = mapped_column(
        Integer, ForeignKey("personal_checkins.id"), nullable=False
    )
    user_id = mapped_column(Text, ForeignKey("users.id"), nullable=False)
    timestamp = mapped_column(Text, nullable=False)
    decision = mapped_column(Text, nullable=False)
    recipient_contact_ids = mapped_column(Text, nullable=True)


class SleepLog(Base):
    __tablename__ = "sleep_logs"

    id = mapped_column(Integer, primary_key=True, autoincrement=True)
    user_id = mapped_column(Text, ForeignKey("users.id"), nullable=False)
    date = mapped_column(Text, nullable=False)
    hours = mapped_column(Float, nullable=False)
    quality = mapped_column(Text, nullable=True)
    note = mapped_column(Text, nullable=True)


class ResearchParticipant(Base):
    __tablename__ = "research_participants"

    research_id = mapped_column(Text, primary_key=True, default=lambda: str(uuid4()))
    consent_given = mapped_column(Boolean, nullable=False)
    consent_version = mapped_column(Text, nullable=False)
    consent_timestamp = mapped_column(Text, nullable=False)
    withdrawn = mapped_column(Boolean, nullable=False, default=False)
    withdrawn_at = mapped_column(Text, nullable=True)


class ResearchSubmission(Base):
    __tablename__ = "research_submissions"

    id = mapped_column(Integer, primary_key=True, autoincrement=True)
    research_id = mapped_column(
        Text, ForeignKey("research_participants.research_id"), nullable=False
    )
    timestamp = mapped_column(Text, nullable=False)
    dataset_version = mapped_column(Text, nullable=True)
    source = mapped_column(Text, nullable=False)
    features = mapped_column(Text, nullable=False)
    extra_fields = mapped_column(Text, nullable=True)
    epds_items = mapped_column(Text, nullable=False)
    epds_total = mapped_column(Integer, nullable=False)
    epds_label = mapped_column(Integer, nullable=False)
