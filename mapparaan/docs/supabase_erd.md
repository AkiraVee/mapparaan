# Mapparaan Supabase ERD

This ERD reflects the latest Supabase Table Editor screenshots supplied for
this project. The Mermaid identifier `auth_users` represents Supabase's
`auth.users` table. The profile table is `public.users`, matching the checked-in
`20261027` migration.

```mermaid
erDiagram
    auth_users ||--o| users : "one-to-one (id; profile optional)"
    auth_users ||--o| user_preferences : "one-to-one (user_id is the PK)"
    auth_users ||--o{ saved_places : "one-to-many (user_id)"
    auth_users ||--o{ memory_pins : "one-to-many (user_id)"
    auth_users ||--o{ trip_history : "one-to-many (user_id)"
    auth_users ||--o{ friend_invites : "one-to-many (inviter_id)"
    auth_users o|--o{ friend_invites : "one-to-many (accepted_by, optional)"
    auth_users ||--o{ friendships : "one-to-many (user_a)"
    auth_users ||--o{ friendships : "one-to-many (user_b)"
    memory_pins ||--o{ memory_pin_shares : "one-to-many (memory_pin_id)"
    auth_users ||--o{ memory_pin_shares : "one-to-many (friend_id)"
    friendships ||--o{ memory_pin_shares : "one-to-many (friendship_id)"

    auth_users {
        uuid id PK
    }
    users {
        uuid id PK, FK
        text full_name
        timestamptz created_at
    }
    user_preferences {
        uuid user_id PK, FK
        text passenger_type
        text theme_mode
        text color_palette
        boolean use_metric_units
        boolean high_contrast_map
        boolean compact_ui
    }
    saved_places {
        text id PK
        uuid user_id FK
        text name
        text subtitle
        geography geom
        timestamptz created_at
    }
    memory_pins {
        uuid id PK
        uuid user_id FK
        text place_name
        text address
        geography geom
        text image_url
        timestamptz created_at
        text image_path
    }
    trip_history {
        uuid id PK
        uuid user_id FK
        text origin_name
        text dest_name
        text preference
        int4 duration_minutes
        float8 fare_estimate
        text route_summary
        timestamptz created_at
    }
    friend_invites {
        uuid id PK
        uuid inviter_id FK
        text token_hash
        timestamptz created_at
        timestamptz expires_at
        timestamptz accepted_at
        uuid accepted_by FK
        timestamptz revoked_at
    }
    friendships {
        uuid id PK
        uuid user_a FK
        uuid user_b FK
        timestamptz created_at
        timestamptz accepted_at
    }
    memory_pin_shares {
        uuid id PK
        uuid memory_pin_id FK
        uuid friend_id FK
        uuid friendship_id FK
        text area_code
        timestamptz created_at
    }
    spatial_ref_sys {
        integer srid PK
        varchar auth_name
        integer auth_srid
        varchar srtext
        varchar proj4text
    }
```

### Relationship cardinalities

- **One-to-one:** `auth.users` ↔ `public.users` via `id` and `auth.users` ↔
  `user_preferences` via `user_id`. Each account can have zero or one row in
  either table; each profile/preferences row belongs to exactly one account.
- **One-to-many / many-to-one:** `auth.users` → `saved_places`, `memory_pins`,
  `trip_history`, and `friendships`; the inverse from each child row to its
  owning user is many-to-one. `memory_pins`, `friendships`, and recipient
  `auth.users` each have one-to-many relationships to `memory_pin_shares`;
  from a share to each referenced row, the relationship is many-to-one.
  `friend_invites` has a many-to-one `inviter_id` and an optional many-to-one
  `accepted_by`.
- **Many-to-many:** `auth.users` ↔ `auth.users` through `friendships`, using
  `user_a` and `user_b`; `memory_pins` ↔ recipient `auth.users` through
  `memory_pin_shares`, using `memory_pin_id` and `friend_id`.

The owner of each share is derived from `memory_pins.user_id`; it is not stored
again in `memory_pin_shares`. `(memory_pin_id, friend_id)` is unique, while
`memory_pin_shares.id` remains the table's primary key. A database trigger
validates that the referenced `friendship_id` joins the pin owner to the
recipient.

`spatial_ref_sys` is PostGIS reference metadata and has no application
relationship in this ERD. The `geography_columns` and `geometry_columns`
entries shown in Supabase are PostGIS metadata views, not application tables,
so they are omitted. Supabase Storage's `storage.objects` is also omitted; it
is a storage table, not one of the application's relational tables.

### Normalization and verification limits

The design separates accounts, preferences, saved places, pins, trip history,
invitations, and share records, with `friendships` and `memory_pin_shares`
serving as relationship tables. The follow-up
`20261028_normalize_memory_pin_shares.sql` removes the duplicated
`memory_pin_shares.owner_id`; the pin is the single source of ownership. It
also validates existing shares before migration and adds triggers that keep
the pin owner, recipient, and friendship consistent on future writes and
parent-row updates.

The latest Table Editor screenshots show `public.users` with `id`, `full_name`,
and `created_at`; this agrees with the `public.users` references in the
checked-in `20261023` and `20261027` migrations. Those screenshots also show
the application tables included here. The screenshot and incremental
migrations do not display every database constraint, so they cannot certify
every formal normal form or prove the follow-up migration has been applied.
The ERD reflects the normalized schema after applying the follow-up migration;
the live database remains unchanged until that migration is run successfully.

For a visual, editable version, open
[`supabase_erd.drawio`](supabase_erd.drawio) in diagrams.net or the Draw.io
extension in VS Code.
