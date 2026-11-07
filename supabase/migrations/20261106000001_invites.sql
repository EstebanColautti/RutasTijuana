create table public.catalog_invitations (
  email text primary key,
  token uuid not null default gen_random_uuid(),
  state text not null default 'pending' check (state in ('pending','active','revoked')),
  user_id uuid unique
);
alter table public.catalog_invitations enable row level security;
revoke all on public.catalog_invitations from anon, authenticated;

create function public.request_catalog_invitation(address text) returns jsonb
language plpgsql security definer set search_path='' as $$
declare invitation public.catalog_invitations%rowtype;
begin
  if public.catalog_role() is distinct from 'admin' then raise insufficient_privilege; end if;
  address := lower(trim(address));
  if address is null or length(address)>254 or address !~ '^[^[:space:]@]+@[^[:space:]@]+[.][^[:space:]@]+$'
    then raise exception 'Correo inválido' using errcode='22023'; end if;
  insert into public.catalog_invitations(email) values(address) on conflict do nothing;
  select * into invitation from public.catalog_invitations where email=address;
  return jsonb_build_object('state',invitation.state,'token',invitation.token);
end;
$$;

create function public.complete_catalog_invitation(address text, proof uuid, administrator uuid) returns boolean
language plpgsql security definer set search_path='' as $$
declare invitation public.catalog_invitations%rowtype;
declare identity uuid;
begin
  if not exists(select 1 from public.catalog_members where user_id=administrator and role='admin')
    then raise insufficient_privilege; end if;
  select * into invitation from public.catalog_invitations where email=address and token=proof for update;
  if not found or invitation.state='revoked' then raise insufficient_privilege; end if;
  if invitation.state='active' then return true; end if;
  select id into identity from auth.users
    where lower(email)=address and raw_user_meta_data->>'catalog_invitation'=proof::text;
  if identity is null then return false; end if;
  insert into public.catalog_members(user_id,role) values(identity,'editor') on conflict do nothing;
  update public.catalog_invitations set user_id=identity,state='active' where email=address;
  insert into public.catalog_audit(actor,action) values(administrator,'invite-editor');
  return true;
end;
$$;

create or replace function public.revoke_catalog_editor(target uuid) returns void
language plpgsql security definer set search_path='' as $$
begin
  if public.catalog_role() is distinct from 'admin' then raise insufficient_privilege; end if;
  update public.catalog_invitations set state='revoked' where user_id=target;
  delete from public.catalog_members where user_id=target and role='editor';
  if not found then raise exception 'Editor inexistente'; end if;
  insert into public.catalog_audit(actor,action) values(auth.uid(),'revoke-editor');
end;
$$;

revoke all on function public.request_catalog_invitation(text) from public;
revoke all on function public.complete_catalog_invitation(text,uuid,uuid) from public, anon, authenticated;
grant execute on function public.request_catalog_invitation(text) to authenticated;
grant execute on function public.complete_catalog_invitation(text,uuid,uuid) to service_role;
