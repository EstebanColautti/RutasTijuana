alter function public.publish_catalog(bigint,text) rename to publish_catalog_itinerary;
revoke all on function public.publish_catalog_itinerary(bigint,text) from public,anon,authenticated;

create function public.publish_catalog(expected_revision bigint,expected_hash text) returns uuid
language plpgsql security definer set search_path='' as $$
declare document jsonb; item jsonb; fields jsonb; roles text[]; contacts text[]; official integer:=0; dates text[]; civil date;
begin
  if public.catalog_role() is distinct from 'admin' then raise insufficient_privilege; end if;
  select d.document into document from public.catalog_drafts d where id=1 for update;
  for item in select value from jsonb_array_elements(public.catalog_projection(document,'preview')->'features') loop
    fields:=item->'information'->'fields';
    select array_agg(value->>'value') into dates from jsonb_array_elements(fields) where value->>'category'='updated-at';
    if dates is not null then
      if cardinality(dates)<>1 then raise exception 'Revisa la fecha de %',item->>'name'; end if;
      if dates[1] ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then
        civil:=dates[1]::date;
        if to_char(civil,'YYYY-MM-DD')<>dates[1] then raise exception 'Fecha inválida'; end if;
      elsif dates[1] ~ '^[0-9]{2}/[0-9]{2}/[0-9]{4}$' then
        civil:=to_date(dates[1],'DD/MM/YYYY');
        if to_char(civil,'DD/MM/YYYY')<>dates[1] then raise exception 'Fecha inválida'; end if;
      else raise exception 'Revisa la fecha de %',item->>'name';
      end if;
    end if;
    select array_agg(value->>'value') into roles from jsonb_array_elements(fields) where value->>'category'='service-role';
    if roles is not null then
      if cardinality(roles)<>1 or roles[1] not in ('contact','notices') or item->>'kind'<>'reference'
        then raise exception 'Revisa el servicio de %',item->>'name'; end if;
      if roles[1]='contact' then
        official:=official+1;
        select array_agg(value->>'value') into contacts from jsonb_array_elements(fields) where value->>'category'='contact';
        if cardinality(contacts) is distinct from 1 or contacts[1] !~ '^https://[^/@?#[:space:]]+([/?#][^[:space:]]*)?$'
          then raise exception 'Revisa el contacto de %',item->>'name'; end if;
      end if;
    end if;
  end loop;
  if official>1 then raise exception 'Conserva un único contacto oficial.'; end if;
  return public.publish_catalog_itinerary(expected_revision,expected_hash);
end;
$$;
revoke all on function public.publish_catalog(bigint,text) from public;
grant execute on function public.publish_catalog(bigint,text) to authenticated;
