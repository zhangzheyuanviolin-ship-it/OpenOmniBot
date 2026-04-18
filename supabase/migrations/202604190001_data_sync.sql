create table if not exists public.sync_namespaces (
  namespace text primary key,
  sync_secret text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.sync_devices (
  namespace text not null references public.sync_namespaces(namespace) on delete cascade,
  device_id text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  primary key (namespace, device_id)
);

create table if not exists public.sync_documents (
  namespace text not null references public.sync_namespaces(namespace) on delete cascade,
  doc_type text not null,
  doc_sync_id text not null,
  content_hash text not null default '',
  deleted boolean not null default false,
  payload jsonb not null default '{}'::jsonb,
  updated_by_device text not null default '',
  updated_at timestamptz not null default now(),
  primary key (namespace, doc_type, doc_sync_id)
);

create table if not exists public.sync_files (
  namespace text not null references public.sync_namespaces(namespace) on delete cascade,
  relative_path text not null,
  content_hash text not null default '',
  object_key text not null default '',
  size_bytes bigint not null default 0,
  last_modified_at bigint not null default 0,
  deleted boolean not null default false,
  updated_by_device text not null default '',
  updated_at timestamptz not null default now(),
  primary key (namespace, relative_path)
);

create table if not exists public.sync_change_log (
  cursor bigint generated always as identity primary key,
  namespace text not null references public.sync_namespaces(namespace) on delete cascade,
  doc_type text not null,
  doc_sync_id text not null,
  op_id text not null unique,
  op_type text not null,
  content_hash text not null default '',
  device_id text not null,
  body jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists idx_sync_change_log_namespace_cursor
  on public.sync_change_log(namespace, cursor);

create table if not exists public.sync_request_nonces (
  namespace text not null references public.sync_namespaces(namespace) on delete cascade,
  device_id text not null,
  nonce text not null,
  created_at timestamptz not null default now(),
  primary key (namespace, device_id, nonce)
);

create index if not exists idx_sync_request_nonces_created_at
  on public.sync_request_nonces(created_at);

comment on table public.sync_namespaces is
  'Direct-sync namespaces for Omnibot self-hosted sync. sync_secret is managed by the namespace owner.';

comment on table public.sync_change_log is
  'Append-only cursor log for idempotent pull. Keep tombstones for at least 30 days before external cleanup.';
