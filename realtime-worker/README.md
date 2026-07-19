# Taskveil realtime Worker

This Worker is a lossy foreground wake-up provider. PostgreSQL and the existing
HTTPS push/pull API remain the only sync authority. The Worker never stores or
forwards record data, cursors, tenant UUIDs, or device UUIDs.

## Routes

- `GET /v1/connect` requires `Upgrade: websocket` and a 300-second ticket in
  `Authorization: Bearer <ticket>`.
- `POST /v1/publish` requires the ADR-019 key ID, Unix timestamp, and HMAC
  headers. A valid request fans out exactly `{"v":1,"type":"changed"}`.

Both routes select the tenant Durable Object through
`REALTIME_CHANNELS.jurisdiction("eu").getByName(opaqueChannel)`. The test suite
sets `TEST_ONLY_UNRESTRICTED_NAMESPACE=enabled` because the pinned local
`workerd` does not implement jurisdiction restrictions. That binding is absent
from `wrangler.jsonc` and must never be configured in a deployed environment.

## Secret bindings

Deployment requires these eight secret/text bindings. Each key value is a
base64url-no-padding encoding of exactly 32 bytes; key IDs match
`[A-Za-z0-9_-]{1,32}`.

- `TICKET_KEY_CURRENT_ID` / `TICKET_KEY_CURRENT`
- `TICKET_KEY_PREVIOUS_ID` / `TICKET_KEY_PREVIOUS`
- `PUBLISH_KEY_CURRENT_ID` / `PUBLISH_KEY_CURRENT`
- `PUBLISH_KEY_PREVIOUS_ID` / `PUBLISH_KEY_PREVIOUS`

No production values belong in this repository. The values in
`vitest.config.ts` and `test/fixtures/realtime-hmac-v1.json` are intentionally
public deterministic test material.

## Observability

Each connect or publish outcome emits one JSON object containing only an
allowlisted `event` field. The possible values are
`realtime_connect_succeeded`, `realtime_connect_failed`,
`realtime_publish_succeeded`, and `realtime_publish_failed`. Tickets, URLs,
opaque channel/device tags, UUIDs, request bodies, and record metadata are never
included. Provider-specific log metadata must not be treated as a place to add
those values.

## Local verification

Use Node.js 24.18.0 as pinned by `.node-version`.

```sh
npm ci
npm run typecheck
npm test
npm run build
```

`npm run build` invokes `wrangler deploy --dry-run`; it does not deploy.
