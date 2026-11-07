alter function public.publish_catalog(bigint,text) rename to publish_catalog_snapshot;
revoke all on function public.publish_catalog_snapshot(bigint,text) from public, anon, authenticated;

create function public.publish_catalog(expected_revision bigint, expected_hash text)
returns uuid language plpgsql security definer set search_path='' as $$
declare
  document jsonb;
  features jsonb;
  route jsonb;
  ordering text[];
  shape text[];
  ids jsonb;
begin
  if public.catalog_role() is distinct from 'admin' then raise insufficient_privilege; end if;
  if expected_revision is null or expected_hash is null or expected_hash !~ '^[0-9a-f]{64}$' then
    raise exception 'Confirma una vista previa válida antes de publicar.' using errcode='22023';
  end if;
  select d.document into document from public.catalog_drafts d where id=1 for update;
  features := public.catalog_projection(document,'preview')->'features';
  for route in select value from jsonb_array_elements(features) where value->>'kind'='route' loop
    select array_agg(value->>'value') filter (where value->>'category'='stop-order'),
           array_agg(trim(value->>'value')) filter (where value->>'category'='route-shape')
      into ordering, shape
      from jsonb_array_elements(route->'information'->'fields');
    if ordering is null and shape is null then continue; end if;
    if cardinality(ordering) is distinct from 1 or cardinality(shape) is distinct from 1
       or shape[1] not in ('linear','circular') then
      raise exception 'Itinerario incompleto en %', route->>'name' using errcode='22023';
    end if;
    begin
      ids := ordering[1]::jsonb;
    exception when invalid_text_representation then
      raise exception 'Orden de paradas inválido en %', route->>'name' using errcode='22023';
    end;
    if jsonb_typeof(ids) is distinct from 'array' then
      raise exception 'Orden de paradas inválido en %', route->>'name' using errcode='22023';
    end if;
    if jsonb_array_length(ids)<2 or exists (
      select 1 from jsonb_array_elements(ids) a(id)
      where jsonb_typeof(a.id)<>'string' or not exists (
        select 1 from jsonb_array_elements(features) f(item)
        where f.item->'id'=a.id and f.item->>'kind'='stop' and f.item->'geometry'->>'type'='Point'
      )
    ) or exists (
      select 1 from jsonb_array_elements(ids) a(id) group by a.id having count(*)>1
    ) then
      raise exception 'Revisa las paradas incluidas y su orden en %', route->>'name' using errcode='22023';
    end if;
  end loop;
  return public.publish_catalog_snapshot(expected_revision,expected_hash);
end;
$$;
revoke all on function public.publish_catalog(bigint,text) from public;
grant execute on function public.publish_catalog(bigint,text) to authenticated;
