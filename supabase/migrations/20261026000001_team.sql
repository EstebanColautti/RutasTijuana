create function public.revoke_catalog_editor(target uuid) returns void language plpgsql security definer set search_path='' as $$
begin
  if public.catalog_role()<>'admin' or public.catalog_role() is null then raise insufficient_privilege; end if;
  delete from public.catalog_members where user_id=target and role='editor';
  if not found then raise exception 'Editor inexistente'; end if;
  insert into public.catalog_audit(actor,action) values(auth.uid(),'revoke-editor');
end;
$$;
revoke all on function public.revoke_catalog_editor(uuid) from public;
grant execute on function public.revoke_catalog_editor(uuid) to authenticated;
