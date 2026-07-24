# sqlx-sqlite lockfile shim

Taskveil uses SQLx only for the server's PostgreSQL access. SQLx 0.9.0 still
places its optional `sqlx-sqlite` dependency in the workspace lockfile, where
its `libsqlite3-sys <0.38` requirement conflicts with the client's
`rusqlite 0.40` / `libsqlite3-sys 0.38` SQLCipher dependency.

This package is a lockfile-resolution shim, not an SQLite driver. It is patched
over `sqlx-sqlite` and is never built by Taskveil's PostgreSQL-only SQLx feature
set. If a future change enables SQLx SQLite, compilation fails intentionally.

Remove this shim when an SQLx release accepts `libsqlite3-sys 0.38` or later.
