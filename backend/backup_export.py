"""Create a contact-stripped SQLite backup or export complete research CSV data."""

import argparse
import csv
import json
import math
import os
import sqlite3
import sys
from pathlib import Path

from config import DATABASE_PATH, FEATURE_NAMES


EPDS_COLUMN_NAMES = tuple(f"epds_item_{index}" for index in range(1, 11))
METADATA_COLUMNS = (
    "research_id",
    "submission_id",
    "submitted_at",
    "dataset_version",
    "source",
    "consent_version",
)


def _readonly_connection(database_path):
    path = Path(database_path).expanduser().resolve(strict=True)
    if not path.is_file():
        raise FileNotFoundError(f"Database file does not exist: {path}")
    return sqlite3.connect(f"{path.as_uri()}?mode=ro", uri=True)


def _quote_identifier(identifier):
    return '"' + identifier.replace('"', '""') + '"'


def _table_metadata(connection):
    tables = connection.execute(
        "SELECT name, sql FROM sqlite_master "
        "WHERE type = 'table' ORDER BY name"
    ).fetchall()
    result = {}
    for table_name, create_sql in tables:
        columns = connection.execute(
            f"PRAGMA table_info({_quote_identifier(table_name)})"
        ).fetchall()
        result[table_name] = (create_sql, columns)
    return result


def _row_counts(connection, table_metadata):
    return {
        table_name: connection.execute(
            f"SELECT COUNT(*) FROM {_quote_identifier(table_name)}"
        ).fetchone()[0]
        for table_name in table_metadata
    }


def _create_output_file(path):
    descriptor = os.open(path, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
    return os.fdopen(descriptor, "wb")


def _remove_output_and_sidecars(path):
    for suffix in ("", "-wal", "-shm", "-journal"):
        candidate = Path(str(path) + suffix)
        try:
            candidate.unlink()
        except FileNotFoundError:
            pass


def _prepare_new_output(output_path, database_path):
    output_path = Path(output_path).expanduser().resolve()
    database_path = Path(database_path).expanduser().resolve(strict=True)
    if output_path == database_path:
        raise ValueError("Output path must not resolve to the source database.")
    if output_path.exists():
        raise FileExistsError(f"Output already exists: {output_path}")
    if not output_path.parent.is_dir():
        raise FileNotFoundError(
            f"Output directory does not exist: {output_path.parent}"
        )
    return output_path, database_path


def create_backup(database_path, output_path):
    output_path, database_path = _prepare_new_output(output_path, database_path)
    output_created = False
    source = None
    destination = None
    try:
        source = _readonly_connection(database_path)
        source_metadata = _table_metadata(source)
        source_counts = _row_counts(source, source_metadata)

        with _create_output_file(output_path):
            output_created = True

        destination = sqlite3.connect(output_path)
        destination.execute("PRAGMA journal_mode=DELETE")
        source.backup(destination)
        destination.execute("DELETE FROM contacts")
        destination.commit()
        destination.execute("VACUUM")
        destination.commit()

        integrity = destination.execute("PRAGMA integrity_check").fetchone()[0]
        if integrity != "ok":
            raise RuntimeError(f"Backup integrity check failed: {integrity}")

        backup_metadata = _table_metadata(destination)
        if backup_metadata != source_metadata:
            raise RuntimeError("Backup table definitions differ from the source.")

        backup_counts = _row_counts(destination, backup_metadata)
        expected_counts = dict(source_counts)
        if "contacts" not in expected_counts:
            raise RuntimeError("Source database does not contain the contacts table.")
        expected_counts["contacts"] = 0
        if backup_counts != expected_counts:
            raise RuntimeError(
                f"Backup table row counts differ: expected {expected_counts}, "
                f"got {backup_counts}."
            )

        destination.close()
        destination = None
        source.close()
        source = None

        for suffix in ("-wal", "-shm", "-journal"):
            sidecar = Path(str(output_path) + suffix)
            if sidecar.exists():
                sidecar.unlink()
        if any(Path(str(output_path) + suffix).exists() for suffix in ("-wal", "-shm")):
            raise RuntimeError("Output database sidecar remains after backup.")

        print(f"Backup created: {output_path}")
        print("Integrity check: ok")
        print("Table definitions: match")
        print(f"Table row counts: {json.dumps(backup_counts, sort_keys=True)}")
        print("Output WAL/SHM sidecars: none")
    except Exception:
        if destination is not None:
            destination.close()
        if source is not None:
            source.close()
        if output_created:
            _remove_output_and_sidecars(output_path)
        raise


def _reject_duplicate_keys(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"Duplicate JSON object key: {key}")
        result[key] = value
    return result


def _parse_json(value, field_name):
    try:
        return json.loads(value, object_pairs_hook=_reject_duplicate_keys)
    except (TypeError, json.JSONDecodeError, ValueError) as exc:
        raise ValueError(f"Invalid JSON in {field_name}.") from exc


def _is_finite_number(value):
    return (
        not isinstance(value, bool)
        and isinstance(value, (int, float))
        and (not isinstance(value, float) or math.isfinite(value))
    )


def _valid_feature_map(value):
    if not isinstance(value, dict) or set(value) != set(FEATURE_NAMES):
        return False
    for name in FEATURE_NAMES:
        feature_value = value[name]
        if name == "Abuse" and feature_value is None:
            continue
        if isinstance(feature_value, str):
            continue
        if _is_finite_number(feature_value):
            continue
        return False
    return True


def _valid_epds_items(value):
    if not isinstance(value, list) or len(value) != len(EPDS_COLUMN_NAMES):
        return False
    return all(
        item is not None and (isinstance(item, str) or _is_finite_number(item))
        for item in value
    )


def _csv_value(value):
    if value is None:
        return ""
    if isinstance(value, str) and value[:1] in {"=", "+", "-", "@", "\t", "\r"}:
        return "'" + value
    if isinstance(value, (dict, list)):
        value = json.dumps(value, ensure_ascii=False, separators=(",", ":"))
        if value[:1] in {"=", "+", "-", "@", "\t", "\r"}:
            return "'" + value
    return value


def _extra_value(value):
    if isinstance(value, (dict, list)):
        return json.dumps(value, ensure_ascii=False, separators=(",", ":"))
    return value


def _complete_submission(submission):
    features = _parse_json(submission["features"], "research_submissions.features")
    epds_items = _parse_json(
        submission["epds_items"], "research_submissions.epds_items"
    )
    if not _valid_feature_map(features) or not _valid_epds_items(epds_items):
        return None
    if not isinstance(submission["epds_total"], int) or isinstance(
        submission["epds_total"], bool
    ):
        return None
    if not isinstance(submission["epds_label"], int) or isinstance(
        submission["epds_label"], bool
    ):
        return None

    extra_fields_raw = submission["extra_fields"]
    if extra_fields_raw is None:
        extra_fields = {}
    else:
        extra_fields = _parse_json(
            extra_fields_raw, "research_submissions.extra_fields"
        )
        if not isinstance(extra_fields, dict):
            return None
    return features, epds_items, extra_fields


def export_research(database_path, output_path):
    if len(FEATURE_NAMES) != 28 or len(set(FEATURE_NAMES)) != 28:
        raise RuntimeError("config.FEATURE_NAMES must contain 28 unique names.")
    output_path, database_path = _prepare_new_output(output_path, database_path)
    output_created = False
    source = None
    try:
        source = _readonly_connection(database_path)
        required_columns = {
            "research_participants": {
                "research_id",
                "consent_given",
                "consent_version",
                "withdrawn",
            },
            "research_submissions": {
                "id",
                "research_id",
                "timestamp",
                "dataset_version",
                "source",
                "features",
                "extra_fields",
                "epds_items",
                "epds_total",
                "epds_label",
            },
        }
        table_names = {
            row[0]
            for row in source.execute(
                "SELECT name FROM sqlite_master WHERE type = 'table'"
            ).fetchall()
        }
        if not set(required_columns).issubset(table_names):
            raise RuntimeError("Database is missing required research tables.")
        for table, expected in required_columns.items():
            actual = {
                row[1]
                for row in source.execute(
                    f"PRAGMA table_info({_quote_identifier(table)})"
                ).fetchall()
            }
            if not expected.issubset(actual):
                raise RuntimeError(f"Database schema is missing columns in {table}.")

        submissions = source.execute(
            """
            SELECT s.id, s.research_id, s.timestamp, s.dataset_version, s.source,
                   s.features, s.extra_fields, s.epds_items, s.epds_total,
                   s.epds_label, p.consent_given, p.consent_version, p.withdrawn
            FROM research_submissions AS s
            LEFT JOIN research_participants AS p
                ON p.research_id = s.research_id
            ORDER BY s.id
            """
        ).fetchall()

        participants_seen = {row[1] for row in submissions if row[1] is not None}
        withdrawn_skipped = 0
        consent_skipped = 0
        incomplete_skipped = 0
        complete_rows = []
        extra_keys = set()

        for row in submissions:
            submission = {
                "id": row[0],
                "research_id": row[1],
                "timestamp": row[2],
                "dataset_version": row[3],
                "source": row[4],
                "features": row[5],
                "extra_fields": row[6],
                "epds_items": row[7],
                "epds_total": row[8],
                "epds_label": row[9],
                "consent_given": row[10],
                "consent_version": row[11],
                "withdrawn": row[12],
            }
            if submission["withdrawn"] == 1:
                withdrawn_skipped += 1
                continue
            if submission["consent_given"] != 1:
                consent_skipped += 1
                continue

            try:
                complete = _complete_submission(submission)
            except ValueError:
                complete = None
            if complete is None:
                incomplete_skipped += 1
                continue

            features, epds_items, extra_fields = complete
            extra_keys.update(extra_fields)
            complete_rows.append((submission, features, epds_items, extra_fields))

        extra_columns = [f"extra_{key}" for key in sorted(extra_keys)]
        header = [
            *METADATA_COLUMNS,
            *FEATURE_NAMES,
            *EPDS_COLUMN_NAMES,
            "epds_total",
            "epds_label",
            *extra_columns,
        ]

        with _create_output_file(output_path) as binary_output:
            output_created = True
            import io

            text_output = io.TextIOWrapper(binary_output, encoding="utf-8", newline="")
            writer = csv.writer(text_output)
            writer.writerow(header)
            for submission, features, epds_items, extra_fields in complete_rows:
                row_values = [
                    submission["research_id"],
                    submission["id"],
                    submission["timestamp"],
                    submission["dataset_version"],
                    submission["source"],
                    submission["consent_version"],
                ]
                row_values.extend(features[name] for name in FEATURE_NAMES)
                row_values.extend(epds_items)
                row_values.extend(
                    (submission["epds_total"], submission["epds_label"])
                )
                row_values.extend(
                    _extra_value(extra_fields.get(key)) for key in sorted(extra_keys)
                )
                writer.writerow([_csv_value(value) for value in row_values])
            text_output.flush()
            text_output.detach()

        source.close()
        source = None

        print(f"CSV export created: {output_path}")
        print(f"Participants seen: {len(participants_seen)}")
        print(f"Withdrawn skipped: {withdrawn_skipped}")
        print(f"Consent not recorded skipped: {consent_skipped}")
        print(f"Incomplete skipped: {incomplete_skipped}")
        print(f"Rows written: {len(complete_rows)}")
        print(f"Columns: {json.dumps(header, ensure_ascii=False)}")
    except Exception:
        if source is not None:
            source.close()
        if output_created:
            _remove_output_and_sidecars(output_path)
        raise


def _build_parser():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    for command in ("backup", "export"):
        subparser = commands.add_parser(command)
        subparser.add_argument("--db", default=str(DATABASE_PATH))
        subparser.add_argument("--out", required=True)
    return parser


def main(argv=None):
    args = _build_parser().parse_args(argv)
    try:
        if args.command == "backup":
            create_backup(args.db, args.out)
        else:
            export_research(args.db, args.out)
    except Exception as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
