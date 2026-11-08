create table public.catalog_media (
  id text primary key check(id ~ '^[0-9a-f]{64}$'),
  content bytea not null check(octet_length(content) between 4 and 2097152),
  width integer not null check(width between 1 and 4096),
  height integer not null check(height between 1 and 4096),
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  check(encode(extensions.digest(content,'sha256'),'hex')=id)
);
alter table public.catalog_media enable row level security;
revoke all on public.catalog_media from anon,authenticated;

create function public.catalog_clean_image(payload bytea, expected_width integer, expected_height integer) returns bytea
language plpgsql immutable set search_path='' as $$
declare cursor integer:=2; marker integer; size integer; result bytea:=decode('ffd8','hex'); dimensions boolean:=false; total integer:=octet_length(payload); tail bytea; app_marker integer;
begin
  if total not between 4 and 2097152 or substring(payload from 1 for 2)<>decode('ffd8','hex') or substring(payload from total-1)<>decode('ffd9','hex')
    then raise exception 'Formato de imagen incorrecto'; end if;
  while cursor+3<total loop
    if get_byte(payload,cursor)<>255 then raise exception 'Formato de imagen incorrecto'; end if;
    marker:=get_byte(payload,cursor+1);
    size:=get_byte(payload,cursor+2)*256+get_byte(payload,cursor+3);
    if size<2 or cursor+size+2>total or marker in (0,255,216,217) or marker between 208 and 215 then raise exception 'Formato de imagen incorrecto'; end if;
    if marker in (192,193,194) then
      if size<8 or get_byte(payload,cursor+5)*256+get_byte(payload,cursor+6)<>expected_height
        or get_byte(payload,cursor+7)*256+get_byte(payload,cursor+8)<>expected_width
        or expected_width not between 1 and 4096 or expected_height not between 1 and 4096
        then raise exception 'Dimensiones de imagen incorrectas'; end if;
      dimensions:=true;
    end if;
    if marker=218 then
      if not dimensions then raise exception 'Dimensiones de imagen incorrectas'; end if;
      tail:=substring(payload from cursor+size+3);
      if position(decode('ffd9','hex') in tail)<>octet_length(tail)-1 then raise exception 'Formato de imagen incorrecto'; end if;
      for app_marker in 224..239 loop
        if position(decode('ff'||lpad(to_hex(app_marker),2,'0'),'hex') in tail)>0 then raise exception 'Formato de imagen incorrecto'; end if;
      end loop;
      if position(decode('fffe','hex') in tail)>0 then raise exception 'Formato de imagen incorrecto'; end if;
      return result||substring(payload from cursor+1);
    end if;
    if marker not between 224 and 239 and marker<>254 then result:=result||substring(payload from cursor+1 for size+2); end if;
    cursor:=cursor+size+2;
  end loop;
  raise exception 'Formato de imagen incorrecto';
end;
$$;
revoke all on function public.catalog_clean_image(bytea,integer,integer) from public,anon,authenticated;

create function public.save_catalog_image(image text, width integer, height integer) returns text
language plpgsql security definer set search_path='' as $$
declare payload bytea; key text;
begin
  if public.catalog_role() is null then raise insufficient_privilege; end if;
  if image is null or length(image)>2796204 then raise exception 'Imagen demasiado grande'; end if;
  payload:=public.catalog_clean_image(decode(image,'base64'),width,height);
  key:=encode(extensions.digest(payload,'sha256'),'hex');
  perform pg_advisory_xact_lock(63148821);
  if not exists(select 1 from public.catalog_media where id=key) and (
    (select count(*) from public.catalog_media where created_by=auth.uid() and created_at>=now()-interval '1 day')>=100
    or (select coalesce(sum(octet_length(content)),0) from public.catalog_media)+octet_length(payload)>536870912
  ) then raise exception 'Se alcanzó el límite de imágenes. Intenta más tarde.'; end if;
  insert into public.catalog_media(id,content,width,height,created_by) values(key,payload,width,height,auth.uid()) on conflict(id) do nothing;
  return key;
end;
$$;
revoke all on function public.save_catalog_image(text,integer,integer) from public;
grant execute on function public.save_catalog_image(text,integer,integer) to authenticated;

alter function public.catalog_projection(jsonb,text) rename to catalog_projection_base;
revoke all on function public.catalog_projection_base(jsonb,text) from public,anon,authenticated;
create function public.catalog_projection(d jsonb, version text) returns jsonb
language sql immutable set search_path='' as $$
  select jsonb_set(base,'{features}',coalesce((select jsonb_agg(
    f || case when jsonb_typeof(original->'routeDetails')='object' then jsonb_build_object('routeDetails',
      (select coalesce(jsonb_object_agg(key,value),'{}'::jsonb) from jsonb_each(original->'routeDetails')
        where key in ('code','direction','circular'))) else '{}'::jsonb end
      || case when jsonb_typeof(original->'media')='array' then jsonb_build_object('media',original->'media') else '{}'::jsonb end
    order by f->>'id') from jsonb_array_elements(base->'features') f
    join jsonb_array_elements(d->'features') original on original->>'id'=f->>'id'),'[]'::jsonb))
  from (select public.catalog_projection_base(d,version) base) projection;
$$;
revoke all on function public.catalog_projection(jsonb,text) from public,anon,authenticated;

alter function public.publish_catalog(bigint,text) rename to publish_catalog_services;
revoke all on function public.publish_catalog_services(bigint,text) from public,anon,authenticated;
create function public.publish_catalog(expected_revision bigint,expected_hash text) returns uuid
language plpgsql security definer set search_path='' as $$
declare document jsonb; item jsonb; key text; image_bytes bigint:=0; field_value jsonb;
begin
  if public.catalog_role() is distinct from 'admin' then raise insufficient_privilege; end if;
  select d.document into document from public.catalog_drafts d where id=1 for update;
  for item in select e.value from jsonb_array_elements(public.catalog_projection(document,'preview')->'features') e loop
    if item ? 'routeDetails' then
      if item->>'kind'<>'route' then raise exception 'Metadatos de recorrido incorrectos'; end if;
      for key,field_value in select * from jsonb_each(item->'routeDetails') loop
        if (key='circular' and jsonb_typeof(field_value)<>'boolean') or
          (key in ('code','direction') and (jsonb_typeof(field_value)<>'string' or length(field_value#>>'{}')>4000 or field_value#>>'{}' ~* 'https?:|www\.|[<>]|file://|source_id|xml_path'))
          then raise exception 'Metadatos de recorrido incorrectos'; end if;
      end loop;
    end if;
    if item ? 'media' then
      if jsonb_array_length(item->'media')>6 then raise exception 'Demasiadas imágenes'; end if;
      for field_value in select * from jsonb_array_elements(item->'media') loop
        if jsonb_typeof(field_value)<>'string' or not exists(select 1 from public.catalog_media where id=field_value#>>'{}')
          then raise exception 'Imagen no disponible'; end if;
      end loop;
    end if;
  end loop;
  select coalesce(sum(octet_length(content)),0) into image_bytes from public.catalog_media where id in (
    select jsonb_array_elements_text(coalesce(f->'media','[]'::jsonb)) from jsonb_array_elements(public.catalog_projection(document,'preview')->'features') f);
  if (select count(*) from public.catalog_media where id in (select jsonb_array_elements_text(coalesce(f->'media','[]'::jsonb)) from jsonb_array_elements(public.catalog_projection(document,'preview')->'features') f))>128 then raise exception 'Demasiadas imágenes'; end if;
  if image_bytes+octet_length(public.catalog_projection(document,'preview')::text)>33554432 then raise exception 'Paquete demasiado grande'; end if;
  return public.publish_catalog_services(expected_revision,expected_hash);
end;
$$;
revoke all on function public.publish_catalog(bigint,text) from public;
grant execute on function public.publish_catalog(bigint,text) to authenticated;

create function public.public_catalog_assets(v uuid) returns jsonb
language sql stable security definer set search_path='' as $$
 select coalesce(jsonb_agg(jsonb_build_object('id',m.id,'sha256',m.id,'bytes',octet_length(m.content),'mimeType','image/jpeg',
   'width',m.width,'height',m.height,'downloadURL','?version='||v::text||'&asset='||m.id) order by m.id),'[]'::jsonb)
 from public.catalog_media m where m.id in (
   select jsonb_array_elements_text(coalesce(f->'media','[]'::jsonb)) from public.catalog_versions c,
   lateral jsonb_array_elements(c.content::jsonb->'features') f where c.version=v and c.withdrawn_at is null);
$$;
create function public.public_catalog_image(v uuid, image text) returns text
language sql stable security definer set search_path='' as $$
 select encode(content,'base64') from public.catalog_media where id=image and exists(
   select 1 from jsonb_array_elements(public.public_catalog_assets(v)) a where a->>'id'=image);
$$;
create or replace function public.public_catalog_manifest() returns jsonb
language sql stable security definer set search_path='' as $$
 select jsonb_build_object('version',v.version,'schemaVersion',2,'bytes',v.bytes,'sha256',v.sha256,'assets',public.public_catalog_assets(v.version))
 from public.catalog_current c join public.catalog_versions v using(version) where c.id=1 and v.withdrawn_at is null;
$$;
revoke all on function public.public_catalog_assets(uuid),public.public_catalog_image(uuid,text) from public;
grant execute on function public.public_catalog_assets(uuid),public.public_catalog_image(uuid,text) to anon,authenticated;
create or replace function public.catalog_backup() returns jsonb
language plpgsql security definer set search_path='' as $$
declare document jsonb;
begin
  if public.catalog_role() is distinct from 'admin' then raise insufficient_privilege; end if;
  select d.document into document from public.catalog_drafts d where id=1;
  return jsonb_build_object('backupVersion',1,'document',document,'images',coalesce((
    select jsonb_agg(jsonb_build_object('id',id,'image',encode(content,'base64'),'width',width,'height',height) order by id)
    from public.catalog_media where id in (select jsonb_array_elements_text(coalesce(f->'media','[]'::jsonb)) from jsonb_array_elements(document->'features') f)
  ),'[]'::jsonb));
end;
$$;

create function public.catalog_image(image text) returns text
language plpgsql security definer set search_path='' as $$
begin
  if public.catalog_role() is null then raise insufficient_privilege; end if;
  return (select encode(content,'base64') from public.catalog_media where id=image);
end;
$$;
revoke all on function public.catalog_image(text) from public;
grant execute on function public.catalog_image(text) to authenticated;
