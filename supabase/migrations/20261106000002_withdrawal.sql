alter table public.catalog_versions add column withdrawn_at timestamptz;
alter table public.catalog_versions add column withdrawal_reason text;

create or replace function public.restore_catalog(target uuid) returns void
language plpgsql security definer set search_path='' as $$
begin
  if public.catalog_role() is distinct from 'admin' then raise insufficient_privilege; end if;
  select version from public.catalog_versions where version=target and withdrawn_at is null for update into target;
  if not found then raise exception 'Publicación no disponible'; end if;
  update public.catalog_current set version=target where id=1;
  insert into public.catalog_audit(actor,action,version) values(auth.uid(),'restore',target);
end;
$$;

create function public.withdraw_catalog(target uuid, reason text, replacement uuid default null)
returns void language plpgsql security definer set search_path='' as $$
declare active uuid;
begin
  if public.catalog_role() is distinct from 'admin' then raise insufficient_privilege; end if;
  if reason is null or length(trim(reason)) not between 1 and 500 then
    raise exception 'Indica el motivo de la retirada.';
  end if;
  perform version from public.catalog_versions
    where version in (target,replacement) order by version for update;
  select version into active from public.catalog_current where id=1 for update;
  if active=target then
    if replacement is null or replacement=target or not exists(
      select 1 from public.catalog_versions where version=replacement and withdrawn_at is null
    ) then raise exception 'Elige una publicación disponible como reemplazo.'; end if;
    update public.catalog_current set version=replacement where id=1;
  end if;
  update public.catalog_versions set withdrawn_at=now(),withdrawal_reason=trim(reason)
    where version=target and withdrawn_at is null;
  if not found then raise exception 'Publicación no disponible'; end if;
  insert into public.catalog_audit(actor,action,version) values(auth.uid(),'withdraw',target);
end;
$$;

create or replace function public.public_catalog_manifest() returns jsonb
language sql stable security definer set search_path='' as $$
  select jsonb_build_object('version',v.version,'schemaVersion',2,'bytes',v.bytes,'sha256',v.sha256)
  from public.catalog_current c join public.catalog_versions v using(version)
  where c.id=1 and v.withdrawn_at is null;
$$;
create or replace function public.public_catalog_content(v uuid) returns text
language sql stable security definer set search_path='' as $$
  select content from public.catalog_versions where version=v and withdrawn_at is null;
$$;
create function public.public_catalog_status(cached uuid[]) returns jsonb
language sql stable security definer set search_path='' as $$
  select public.public_catalog_manifest() || jsonb_build_object('withdrawnVersions', coalesce((
    select jsonb_agg(version) from public.catalog_versions
    where cardinality(cached)<=2 and version=any(cached) and withdrawn_at is not null
  ),'[]'::jsonb));
$$;
revoke all on function public.withdraw_catalog(uuid,text,uuid) from public;
grant execute on function public.withdraw_catalog(uuid,text,uuid) to authenticated;
revoke all on function public.public_catalog_status(uuid[]) from public;
grant execute on function public.public_catalog_status(uuid[]) to anon,authenticated;
