import { createClient, type Session } from '@supabase/supabase-js';
import type { Audit, Document, Draft, Preview, Version } from '../../shared/catalog';
const url = import.meta.env.VITE_SUPABASE_URL as string | undefined;
const key = import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY as string | undefined;
export const client =
    url && key
        ? createClient(url, key, {
              auth: {
                  storage: window.sessionStorage,
                  persistSession: true,
                  detectSessionInUrl: true,
              },
          })
        : null;
export interface CatalogAPI {
    role(): Promise<'admin' | 'editor'>;
    draft(): Promise<Draft>;
    save(document: Document, revision: number): Promise<number>;
    preview(): Promise<Preview>;
    publish(preview: Preview): Promise<string>;
    versions(): Promise<Version[]>;
    audit(): Promise<Audit[]>;
    restore(version: string): Promise<void>;
    backup(): Promise<unknown>;
    invite(email: string): Promise<void>;
  members(): Promise<{user_id:string;role:string}[]>;
  revoke(userID:string): Promise<void>;
}
function result<T>(data: T, error: { message: string } | null): T {
    if (error) throw new Error(error.message);
    return data;
}
export function api(): CatalogAPI {
    if (!client) throw new Error('Configura la conexión local.');
    const c = client;
    return {
        async role() {
            const { data, error } = await c.rpc('catalog_role');
            const role = result(data, error);
            if (!['admin', 'editor'].includes(role))
                throw new Error('Tu cuenta no tiene acceso al panel.');
            return role;
        },
        async draft() {
            const { data, error } = await c
                .from('catalog_drafts')
                .select('revision,document,updated_at,updated_by')
                .eq('id', 1)
                .single();
            return result(data, error) as Draft;
        },
        async save(document, revision) {
            const { data, error } = await c.rpc('save_catalog', {
                d: document,
                expected_revision: revision,
            });
            return result(data, error);
        },
        async preview() {
            const { data, error } = await c.rpc('preview_catalog');
            return result(data, error);
        },
        async publish(preview) {
            const { data, error } = await c.rpc('publish_catalog', {
                expected_revision: preview.revision,
                expected_hash: preview.sha256,
            });
            return result(data, error);
        },
        async versions() {
            const { data, error } = await c
                .from('catalog_versions')
                .select('version,sha256,bytes,created_at,created_by')
                .order('created_at', { ascending: false })
                .limit(100);
            return result(data, error) ?? [];
        },
        async audit() {
            const { data, error } = await c
                .from('catalog_audit')
                .select('*')
                .order('id', { ascending: false })
                .limit(100);
            return result(data, error) ?? [];
        },
        async restore(version) {
            const { error } = await c.rpc('restore_catalog', { target: version });
            result(null, error);
        },
        async backup() {
            const { data, error } = await c.rpc('catalog_backup');
            return result(data, error);
        },
        async members() {
      const {data,error}=await c.from('catalog_members').select('user_id,role').order('created_at');
      return result(data,error) ?? [];
    },
    async revoke(userID) {
      const {error}=await c.rpc('revoke_catalog_editor',{target:userID}); result(null,error);
    },
    async invite(email) {
            const { error } = await c.functions.invoke('team', { body: { email } });
            result(null, error);
        },
    };
}
export type { Session };
