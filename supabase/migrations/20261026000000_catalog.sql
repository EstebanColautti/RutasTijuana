create extension if not exists pgcrypto with schema extensions;

create table public.catalog_members (
  user_id uuid primary key,
  role text not null check (role in ('admin','editor')),
  created_at timestamptz not null default now()
);
create table public.catalog_drafts (
  id integer primary key check (id = 1),
  revision bigint not null default 0,
  document jsonb not null default '{"groups":[],"features":[]}',
  updated_at timestamptz not null default now(),
  updated_by uuid
);
insert into public.catalog_drafts(id) values (1);
create table public.catalog_versions (
  version uuid primary key,
  content text not null,
  sha256 text not null,
  bytes integer not null,
  created_at timestamptz not null default now(),
  created_by uuid not null
);
create table public.catalog_current (
  id integer primary key check(id = 1),
  version uuid not null references public.catalog_versions(version)
);
create table public.catalog_audit (
  id bigint generated always as identity primary key,
  actor uuid not null,
  action text not null,
  revision bigint,
  version uuid,
  created_at timestamptz not null default now()
);

create function public.catalog_role() returns text language sql stable security definer
set search_path = '' as $$
  select role from public.catalog_members where user_id = auth.uid()
    and auth.jwt()->>'aal' = 'aal2';
$$;
revoke all on function public.catalog_role() from public;
grant execute on function public.catalog_role() to authenticated;

alter table public.catalog_members enable row level security;
alter table public.catalog_drafts enable row level security;
alter table public.catalog_versions enable row level security;
alter table public.catalog_current enable row level security;
alter table public.catalog_audit enable row level security;
create policy members_read on public.catalog_members for select to authenticated using
  (public.catalog_role() = 'admin' or (user_id = auth.uid() and public.catalog_role() = 'editor'));
create policy drafts_read on public.catalog_drafts for select to authenticated using
  (public.catalog_role() in ('admin','editor'));
create policy versions_read on public.catalog_versions for select to authenticated using
  (public.catalog_role() = 'admin');
create policy audit_read on public.catalog_audit for select to authenticated using
  (public.catalog_role() in ('admin','editor'));
grant select on public.catalog_members,public.catalog_drafts,public.catalog_versions,public.catalog_audit to authenticated;
revoke all on public.catalog_current from anon,authenticated;

create function public.catalog_geometry_valid(g jsonb) returns boolean language plpgsql immutable
set search_path = '' as $$
declare kind text; coords jsonb; p jsonb; part jsonb; ring jsonb;
begin
  kind := g->>'type'; coords := g->'coordinates';
  if jsonb_typeof(coords) is distinct from 'array' or jsonb_array_length(coords) = 0 then return false; end if;
  if kind = 'Point' then
    if jsonb_array_length(coords) not in (2,3) or jsonb_typeof(coords->0) is distinct from 'number'
       or jsonb_typeof(coords->1) is distinct from 'number' then return false; end if;
    if (coords->>0)::numeric not between -180 and 180 or (coords->>1)::numeric not between -90 and 90 then return false; end if;
    if jsonb_array_length(coords) = 3 and jsonb_typeof(coords->2) is distinct from 'number' then return false; end if;
    return true;
  elsif kind = 'LineString' then
    if jsonb_array_length(coords) < 2 then return false; end if;
    for p in select value from jsonb_array_elements(coords) loop
      if not public.catalog_geometry_valid(jsonb_build_object('type','Point','coordinates',p)) then return false; end if;
    end loop;
  elsif kind = 'Polygon' then
    for ring in select value from jsonb_array_elements(coords) loop
      if jsonb_typeof(ring) is distinct from 'array' or jsonb_array_length(ring) < 4 or ring->0 <> ring->(jsonb_array_length(ring)-1)
         or not public.catalog_geometry_valid(jsonb_build_object('type','LineString','coordinates',ring)) then return false; end if;
    end loop;
  elsif kind in ('MultiLineString','MultiPolygon') then
    for part in select value from jsonb_array_elements(coords) loop
      if not public.catalog_geometry_valid(jsonb_build_object('type',case when kind='MultiLineString' then 'LineString' else 'Polygon' end,'coordinates',part)) then return false; end if;
    end loop;
  else return false;
  end if;
  return true;
exception when others then return false;
end;
$$;

create function public.catalog_document_valid(d jsonb) returns boolean language plpgsql immutable
set search_path = '' as $$
declare g jsonb; f jsonb; v jsonb; seen text[] := '{}'; groups text[] := '{}';
begin
  if d is null or jsonb_typeof(d->'groups') is distinct from 'array' or jsonb_typeof(d->'features') is distinct from 'array'
     or octet_length(d::text) > 16777216 or jsonb_array_length(d->'features') > 10000 then return false; end if;
  for g in select value from jsonb_array_elements(d->'groups') loop
    if jsonb_typeof(g->'id') is distinct from 'string' or jsonb_typeof(g->'name') is distinct from 'string' or coalesce(g->>'id','') = '' or coalesce(trim(g->>'name'),'') = '' or g->>'id' = any(groups) then return false; end if;
    groups := array_append(groups,g->>'id');
  end loop;
  for f in select value from jsonb_array_elements(d->'features') loop
    if jsonb_typeof(f->'id') is distinct from 'string' or jsonb_typeof(f->'name') is distinct from 'string' or coalesce(f->>'id','') = '' or coalesce(trim(f->>'name'),'') = '' or f->>'id' = any(seen)
       or not coalesce(f->>'groupID'=any(groups),false)
       or not coalesce(f->>'kind' in ('route','area','reference','stop'),false)
       or not coalesce(f->>'color' ~ '^#[0-9a-fA-F]{6}$',false)
       or jsonb_typeof(f->'included') is distinct from 'boolean'
       or not public.catalog_geometry_valid(f->'geometry') then return false; end if;
    if f->>'kind' = 'route' and f->'geometry'->>'type' not in ('LineString','MultiLineString') then return false; end if;
    if f->>'kind' = 'stop' and f->'geometry'->>'type' <> 'Point' then return false; end if;
    if jsonb_typeof(f->'publicDescription') is distinct from 'string' or jsonb_typeof(f->'publicFields') is distinct from 'array' then return false; end if;
    for v in select value from jsonb_array_elements(f->'publicFields') loop
      if jsonb_typeof(v->'category') is distinct from 'string' or jsonb_typeof(v->'label') is distinct from 'string'
         or jsonb_typeof(v->'value') is distinct from 'string' then return false; end if;
    end loop;
    seen := array_append(seen,f->>'id');
  end loop;
  return true;
exception when others then return false;
end;
$$;

create function public.save_catalog(d jsonb, expected_revision bigint) returns bigint language plpgsql security definer
set search_path = '' as $$
declare next_revision bigint;
begin
  if public.catalog_role() not in ('admin','editor') or public.catalog_role() is null then raise insufficient_privilege; end if;
  if not public.catalog_document_valid(d) then raise exception 'Formato de catálogo incorrecto' using errcode='22023'; end if;
  update public.catalog_drafts set document=d, revision=revision+1,updated_at=now(),updated_by=auth.uid()
    where id=1 and revision=expected_revision returning revision into next_revision;
  if next_revision is null then raise exception 'El borrador cambió. Recarga antes de guardar.' using errcode='40001'; end if;
  insert into public.catalog_audit(actor,action,revision) values(auth.uid(),'save',next_revision);
  return next_revision;
end;
$$;

create function public.catalog_projection(d jsonb, version text) returns jsonb language sql immutable
set search_path = '' as $$
  select jsonb_build_object('schemaVersion',2,'version',version,
    'groups',coalesce((select jsonb_agg(jsonb_build_object('id',g->>'id','name',g->>'name') order by g->>'id')
      from jsonb_array_elements(d->'groups') g where exists(select 1 from jsonb_array_elements(d->'features') f
      where f->>'groupID'=g->>'id' and f->>'included'='true')),'[]'::jsonb),
    'features',coalesce((select jsonb_agg(jsonb_build_object('id',f->>'id','name',f->>'name',
      'groupID',f->>'groupID','kind',f->>'kind','color',f->>'color','geometry',f->'geometry',
      'information',jsonb_build_object('description',f->>'publicDescription','fields',coalesce(
        (select jsonb_agg(jsonb_build_object('category',v->>'category','label',v->>'label','value',v->>'value') order by n)
         from jsonb_array_elements(f->'publicFields') with ordinality t(v,n)),'[]'::jsonb))) order by f->>'id')
      from jsonb_array_elements(d->'features') f where f->>'included'='true'),'[]'::jsonb));
$$;

create function public.preview_catalog() returns jsonb language plpgsql security definer set search_path='' as $$
declare d jsonb; r bigint; body text;
begin
  if public.catalog_role() <> 'admin' or public.catalog_role() is null then raise insufficient_privilege; end if;
  select document,revision into d,r from public.catalog_drafts where id=1;
  body := public.catalog_projection(d,'preview')::text;
  return jsonb_build_object('revision',r,'payload',body,'sha256',encode(extensions.digest(convert_to(body,'UTF8'),'sha256'),'hex'));
end;
$$;

create function public.publish_catalog(expected_revision bigint, expected_hash text) returns uuid language plpgsql security definer set search_path='' as $$
declare d jsonb; r bigint; v uuid := gen_random_uuid(); body text; check_body text;
begin
  if public.catalog_role() <> 'admin' or public.catalog_role() is null then raise insufficient_privilege; end if;
  select document,revision into d,r from public.catalog_drafts where id=1 for update;
  check_body := public.catalog_projection(d,'preview')::text;
  if r<>expected_revision or encode(extensions.digest(convert_to(check_body,'UTF8'),'sha256'),'hex')<>expected_hash
    then raise exception 'La vista previa cambió. Vuelve a abrirla.' using errcode='40001'; end if;
  if not public.catalog_document_valid(d) then raise exception 'Formato de catálogo incorrecto'; end if;
  body := public.catalog_projection(d,v::text)::text;
  if octet_length(body)>16777216 then raise exception 'Catálogo demasiado grande'; end if;
  insert into public.catalog_versions(version,content,sha256,bytes,created_by) values
    (v,body,encode(extensions.digest(convert_to(body,'UTF8'),'sha256'),'hex'),octet_length(body),auth.uid());
  insert into public.catalog_current(id,version) values(1,v) on conflict(id) do update set version=excluded.version;
  insert into public.catalog_audit(actor,action,revision,version) values(auth.uid(),'publish',r,v);
  return v;
end;
$$;

create function public.restore_catalog(target uuid) returns void language plpgsql security definer set search_path='' as $$
begin
  if public.catalog_role()<>'admin' or public.catalog_role() is null then raise insufficient_privilege; end if;
  if not exists(select 1 from public.catalog_versions where version=target) then raise exception 'Versión inexistente'; end if;
  update public.catalog_current set version=target where id=1;
  insert into public.catalog_audit(actor,action,version) values(auth.uid(),'restore',target);
end;
$$;

create function public.public_catalog_manifest() returns jsonb language sql stable security definer set search_path='' as $$
  select jsonb_build_object('version',v.version,'schemaVersion',2,'bytes',v.bytes,'sha256',v.sha256)
  from public.catalog_current c join public.catalog_versions v using(version) where c.id=1;
$$;
create function public.public_catalog_content(v uuid) returns text language sql stable security definer set search_path='' as $$
  select content from public.catalog_versions where version=v;
$$;

create function public.catalog_backup() returns jsonb language plpgsql security definer set search_path='' as $$
begin
  if public.catalog_role()<>'admin' or public.catalog_role() is null then raise insufficient_privilege; end if;
  return jsonb_build_object('backupVersion',1,'document',(select document from public.catalog_drafts where id=1));
end;
$$;

revoke all on function public.save_catalog(jsonb,bigint),public.preview_catalog(),public.publish_catalog(bigint,text),
  public.restore_catalog(uuid),public.catalog_backup(),public.catalog_projection(jsonb,text),
  public.catalog_document_valid(jsonb),public.catalog_geometry_valid(jsonb),public.public_catalog_manifest(),public.public_catalog_content(uuid) from public;
grant execute on function public.save_catalog(jsonb,bigint),public.preview_catalog(),public.publish_catalog(bigint,text),
  public.restore_catalog(uuid),public.catalog_backup() to authenticated;
grant execute on function public.public_catalog_manifest(),public.public_catalog_content(uuid) to anon,authenticated;
