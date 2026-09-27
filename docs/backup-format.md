# Rise Log backup format

Rise Log backups are user-owned, UTF-8 JSON files. The current schema version is **1**. The archive contains the complete persistent state needed to restore cultures, event history, lineage, and deterministic derived status.

A separate CSV export provides a spreadsheet-friendly view of the full event ledger. CSV is export-only and is not accepted for restore.

## Restore contract

Restore always uses explicit **replace** semantics:

1. Rise Log decodes and validates the entire archive without touching the current database.
2. The app shows a preview comparing current and incoming culture/event counts, including cultures/events added and removed.
3. The user must explicitly choose **Replace All Data** and confirm the destructive action.
4. Rise Log replaces the database atomically in one transaction. If any validation or database operation fails, the transaction rolls back and existing data remains unchanged.

There is no merge restore path.

## Top-level JSON object

| Field | Type | Required | Description |
|---|---|---:|---|
| `schema_version` | integer | yes | Archive schema version. Current value: `1`. |
| `app_version` | string | yes | Rise Log app version that produced the archive. Informational; payload compatibility is controlled by `schema_version`. |
| `exported_at` | string | yes | Export time in RFC 3339 / ISO 8601 UTC with milliseconds. |
| `cultures` | array | yes | Complete set of culture records. |
| `events` | array | yes | Complete append-only event ledger including audit timestamps. |

## Culture object

| Field | Type | Required | Description |
|---|---|---:|---|
| `id` | string | yes | Stable culture identifier. Unique in the archive. |
| `name` | string | yes | User-visible culture name. |
| `typePredefined` | string or `null` | conditional | One of `starter`, `kombucha`, `kimchi`, `yogurt`, or `vinegar`. Exactly one of `typePredefined` and `typeCustom` must be populated. |
| `typeCustom` | string or `null` | conditional | Non-empty user-defined type name. |
| `cadenceEveryHours` | integer or `null` | no | User-declared feeding interval in hours. Must be greater than zero if present. |
| `cadenceGraceHours` | integer or `null` | no | Grace window in hours. Non-negative; meaningful only with `cadenceEveryHours`. |
| `createdAt` | string | yes | Culture creation time in RFC 3339 / ISO 8601 UTC with milliseconds. |

## Event object

Every event has these common fields:

| Field | Type | Required | Description |
|---|---|---:|---|
| `id` | string | yes | Stable event identifier. Unique in the archive. |
| `cultureId` | string | yes | ID of a culture in the same archive. |
| `kind` | string | yes | `feed`, `riseCheck`, `bottle`, `bake`, `discard`, `note`, or `split`. |
| `occurredAt` | string | yes | User-visible event time in RFC 3339 / ISO 8601 UTC with milliseconds. |
| `loggedAt` | string | yes | Immutable audit timestamp when the event was recorded. |

Payload fields depend on `kind`; unrelated fields are omitted:

| Kind | Payload fields |
|---|---|
| `feed` | `flourGrams` (number or `null`), `waterGrams` (number or `null`) |
| `riseCheck` | `stage`: `flat`, `rising`, `peaked`, or `falling` |
| `bottle` | none |
| `bake` | `flourUsedGrams` (number or `null`) |
| `discard` | `removedGrams` (number or `null`) |
| `note` | `noteText` (string; required) |
| `split` | `splitParentId` (culture ID in same archive), `separatedAt` (RFC 3339 / ISO 8601 UTC timestamp) |

`split` records rebuild the lineage graph during restore. The archive must contain every referenced child and parent culture, and its lineage must remain acyclic.

## Example schema-v1 archive

```json
{
  "app_version": "0.1.0",
  "cultures": [
    {
      "cadenceEveryHours": 24,
      "cadenceGraceHours": 4,
      "createdAt": "2026-09-20T08:00:00.000Z",
      "id": "culture-rye",
      "name": "Rye Starter",
      "typePredefined": "starter"
    }
  ],
  "events": [
    {
      "cultureId": "culture-rye",
      "flourGrams": 50,
      "id": "event-feed-1",
      "kind": "feed",
      "loggedAt": "2026-09-27T08:01:00.000Z",
      "occurredAt": "2026-09-27T08:00:00.000Z",
      "waterGrams": 50
    },
    {
      "cultureId": "culture-rye",
      "id": "event-note-1",
      "kind": "note",
      "loggedAt": "2026-09-27T12:00:01.000Z",
      "noteText": "Bubbles around the edge",
      "occurredAt": "2026-09-27T12:00:00.000Z"
    }
  ],
  "exported_at": "2026-09-27T18:30:00.000Z",
  "schema_version": 1
}
```

JSON keys are encoded with sorted-key formatting for readability. Decoders must not rely on key order.

## Compatibility and errors

- Rise Log currently reads `schema_version: 1` only.
- A newer or older unsupported version is rejected before any database modification.
- Invalid JSON, missing required fields, duplicate IDs, unknown culture references, invalid timestamps, unsupported event kinds, and malformed payloads are reported as actionable errors.
- Failed validation or failed atomic replacement leaves the current store byte-for-byte untouched.

## CSV ledger export

The CSV export uses UTF-8 and RFC 4180 quoting with `CRLF` line endings. Fields that contain commas, quotes, carriage returns, or newlines are quoted; embedded quotes are doubled. Values starting with `=`, `+`, `-`, or `@` are prefixed with a single quote to reduce spreadsheet formula-injection risk.

Columns, in order:

1. `event_id`
2. `occurred_at`
3. `logged_at`
4. `culture_id`
5. `culture_name`
6. `kind`
7. `summary`
8. `flour_grams`
9. `water_grams`
10. `stage`
11. `flour_used_grams`
12. `removed_grams`
13. `note_text`
14. `split_parent_id`
15. `separated_at`

The CSV is a readable ledger projection, not a backup source. Preserve the JSON archive for restorable backups.

## Privacy

Backup and CSV generation are local-only. Files are written to the app's temporary directory and passed to the iOS system share/save panel after an explicit user action. Rise Log contains no networking APIs, analytics, accounts, or cloud transport; the destination is chosen by the user through iOS.
