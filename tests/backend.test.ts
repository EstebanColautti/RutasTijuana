import { PGlite } from '@electric-sql/pglite';
import { pgcrypto } from '@electric-sql/pglite/contrib/pgcrypto';
import { readFile } from 'node:fs/promises';
import { beforeAll, afterAll, test, expect } from 'vitest';
const db = new PGlite({ extensions: { pgcrypto } });
const admin = '11111111-1111-4111-8111-111111111111',
    editor = '22222222-2222-4222-8222-222222222222',
    outsider = '33333333-3333-4333-8333-333333333333';
const document = {
    groups: [{ id: 'g', name: 'Ejemplo' }],
    features: [
        {
            id: 'r',
            name: 'Recorrido de ejemplo',
            groupID: 'g',
            kind: 'route',
            color: '#2476E8',
            included: true,
            geometry: {
                type: 'LineString',
                coordinates: [
                    [-117, 32.5],
                    [-117.01, 32.51],
                ],
            },
            publicDescription: 'Texto público',
            publicFields: [
                {
                    category: 'fare',
                    label: 'Tarifa',
                    value: '$9',
                    evidence: 'PRIVATE_EVIDENCE',
                    secret: 'PRIVATE_FIELD',
                },
            ],
            privateNotes: 'PRIVATE_NOTE',
            source: { description: 'PRIVATE_SOURCE' },
        },
    ],
};
async function call(
    sql: string,
    params: unknown[] = [],
    user = admin,
    aal = 'aal2',
    role = 'authenticated',
) {
    await db.exec('begin');
    try {
  await db.query("select set_config('request.jwt.claims',$1,true)", [
            JSON.stringify({ sub: user, aal }),
        ]);
        await db.exec('set local role ' + role);
        const r = await db.query(sql, params);
        await db.exec('commit');
        return r.rows as Record<string, any>[];
    } catch (e) {
        await db.exec('rollback');
        throw e;
    }
}
beforeAll(async () => {
    await db.exec(`create role anon; create role authenticated; create role service_role bypassrls; create schema auth; create schema extensions;
 create table auth.users(id uuid primary key,email text,raw_user_meta_data jsonb);
 create function auth.uid() returns uuid language sql stable as $$select (nullif(current_setting('request.jwt.claims',true),'')::jsonb->>'sub')::uuid$$;
 create function auth.jwt() returns jsonb language sql stable as $$select coalesce(nullif(current_setting('request.jwt.claims',true),'')::jsonb,'{}'::jsonb)$$;
 grant usage on schema auth,public to anon,authenticated,service_role; grant execute on all functions in schema auth to anon,authenticated,service_role;`);
    await db.exec(
        (await readFile('supabase/migrations/20261026000000_catalog.sql', 'utf8')).replace(
            /^\uFEFF/,
            '',
        ),
    );
    await db.exec((await readFile('supabase/migrations/20261026000001_team.sql','utf8')).replace(/^\uFEFF/,''));
    await db.exec(await readFile('supabase/migrations/20261106000000_publication.sql', 'utf8'));
    await db.exec(await readFile('supabase/migrations/20261106000001_invites.sql', 'utf8'));
    await db.exec(await readFile('supabase/migrations/20261106000002_withdrawal.sql', 'utf8'));
    await db.exec(await readFile('supabase/migrations/20261106000003_services.sql', 'utf8'));
    await db.query("insert into catalog_members(user_id,role) values ($1,'admin'),($2,'editor')", [
        admin,
        editor,
    ]);
}, 30000);
afterAll(async () => {
    await db.close();
});
test('MFA and invitation are enforced in the database', async () => {
    await expect(
        call('select save_catalog($1::jsonb,0)', [JSON.stringify(document)], editor, 'aal1'),
    ).rejects.toThrow();
    await expect(
        call('select save_catalog($1::jsonb,0)', [JSON.stringify(document)], outsider),
    ).rejects.toThrow();
    await expect(call('select * from catalog_drafts', [], admin, 'aal2', 'anon')).rejects.toThrow();
    expect(await call('select * from catalog_drafts', [], outsider)).toHaveLength(0);
    await expect(
        call("update catalog_members set role='admin' where user_id=$1", [editor], editor),
    ).rejects.toThrow();
});
test('editors save with optimistic concurrency; publication excludes private fields', async () => {
    const saved = await call(
        'select save_catalog($1::jsonb,0) as revision',
        [JSON.stringify(document)],
        editor,
    );
    expect(saved[0].revision).toBe(1);
    await expect(
        call('select save_catalog($1::jsonb,0)', [JSON.stringify(document)], editor),
    ).rejects.toThrow();
    await expect(call('select preview_catalog()', [], editor)).rejects.toThrow();
    const preview = (await call('select preview_catalog() as p'))[0].p;
    expect(preview.payload).not.toContain('PRIVATE');
    await expect(
        call('select publish_catalog($1,$2)', [1, preview.sha256], editor),
    ).rejects.toThrow();
    await expect(call('select publish_catalog($1,$2)', [1, 'different'])).rejects.toThrow();
    const published = (await call('select publish_catalog($1,$2) as v', [1, preview.sha256]))[0].v;
    const manifest = (
        await call('select public_catalog_manifest() as m', [], outsider, 'aal1', 'anon')
    )[0].m;
    expect(manifest.version).toBe(published);
    expect(manifest.bytes).toBeGreaterThan(0);
    const text = (
        await call(
            'select public_catalog_content($1) as body',
            [published],
            outsider,
            'aal1',
            'anon',
        )
    )[0].body;
    expect(JSON.parse(text).features[0].publicDescription).toBeUndefined();
    expect(text).toContain('Texto público');
    expect(text).not.toContain('PRIVATE');
    const { createHash } = await import('node:crypto');
    expect(createHash('sha256').update(text).digest('hex')).toBe(manifest.sha256);
});
test('draft edits do not change snapshots; restoring and backups require admin', async () => {
    const old = (
        await call('select public_catalog_manifest() as m', [], outsider, 'aal1', 'anon')
    )[0].m;
    const changed = structuredClone(document);
    changed.features[0].name = 'Otro recorrido';
    changed.features[0].included = false;
    await call('select save_catalog($1::jsonb,1)', [JSON.stringify(changed)], editor);
    expect(
        (await call('select public_catalog_manifest() as m', [], outsider, 'aal1', 'anon'))[0].m,
    ).toEqual(old);
    const preview = (await call('select preview_catalog() as p'))[0].p;
    await call('select publish_catalog($1,$2)', [2, preview.sha256]);
    await expect(call('select restore_catalog($1)', [old.version], editor)).rejects.toThrow();
    await call('select restore_catalog($1)', [old.version]);
    expect(
        (await call('select public_catalog_manifest() as m', [], outsider, 'aal1', 'anon'))[0].m,
    ).toEqual(old);
    await expect(call('select catalog_backup()', [], editor)).rejects.toThrow();
    const backup = (await call('select catalog_backup() as b'))[0].b;
    expect(backup.document).toEqual(changed);
    await call('select save_catalog($1::jsonb,2)', [JSON.stringify(backup.document)]);
});
test('malformed geometry and incomplete records cannot be saved', async () => {
    for (const d of [
        {},
        { groups: [], features: [{}] },
        {
            ...document,
            features: [
                {
                    ...document.features[0],
                    geometry: { type: 'LineString', coordinates: [[0, 0]] },
                },
            ],
        },
        {
            ...document,
            features: [{ ...document.features[0], publicFields: [{ category: 'fare' }] }],
        },
    ]) {
        await expect(
            call('select save_catalog($1::jsonb,3)', [JSON.stringify(d)], editor),
        ).rejects.toThrow();
    }
});

test('only the administrator can revoke editors', async () => {
  await expect(call('select revoke_catalog_editor($1)', [admin], editor)).rejects.toThrow();
  await expect(call('select revoke_catalog_editor($1)', [admin])).rejects.toThrow();
  await call('select revoke_catalog_editor($1)', [editor]);
  expect(await call('select * from catalog_drafts', [], editor)).toHaveLength(0);
});

test('invitation repair is idempotent and revoked membership stays revoked', async () => {
    const address = 'editor@example.test';
    const pending = await call('select request_catalog_invitation($1) as invite', [address.toUpperCase()]);
    const proof = pending[0].invite.token;
    await expect(call('select request_catalog_invitation($1)', [address], editor)).rejects.toThrow();
    await expect(call('select complete_catalog_invitation($1,$2,$3)', [address, proof, admin])).rejects.toThrow();
    const finish = () => call('select complete_catalog_invitation($1,$2,$3) as done',
        [address, proof, admin], admin, 'aal2', 'service_role');
    expect((await finish())[0].done).toBe(false);
    await db.query('insert into auth.users values($1,$2,$3)', [outsider, address, { catalog_invitation: proof }]);
    expect((await finish())[0].done).toBe(true);
    expect((await finish())[0].done).toBe(true);
    expect((await call('select catalog_role() as role', [], outsider))[0].role).toBe('editor');
    await call('select revoke_catalog_editor($1)', [outsider]);
    await expect(finish()).rejects.toThrow();
    expect((await call('select catalog_role() as role', [], outsider))[0].role).toBeNull();
});

test('publication rejects missing confirmation and inaccessible itinerary stops', async () => {
    const old = (await call('select public_catalog_manifest() as m'))[0].m;
    const baseline = (await call('select preview_catalog() as p'))[0].p;
    await expect(call('select publish_catalog($1,$2)', [null, baseline.sha256])).rejects.toThrow();
    await expect(call('select publish_catalog($1,$2)', [baseline.revision, null])).rejects.toThrow();
    await expect(call('select publish_catalog_snapshot($1,$2)', [baseline.revision, baseline.sha256])).rejects.toThrow();
    const invalid = structuredClone(document);
    invalid.features[0].publicFields.push(
        { category: 'stop-order', label: 'Orden', value: '["missing","missing"]', evidence: '', secret: '' },
        { category: 'route-shape', label: 'Tipo', value: 'linear', evidence: '', secret: '' },
    );
    await call('select save_catalog($1,$2)', [invalid, baseline.revision]);
    const next = (await call('select preview_catalog() as p'))[0].p;
    await expect(call('select publish_catalog($1,$2)', [next.revision, next.sha256])).rejects.toThrow();
    expect((await call('select public_catalog_manifest() as m'))[0].m).toEqual(old);
    await call('select save_catalog($1,$2)', [document, next.revision]);
});

test('withdrawal requires a safe replacement and invalidates old public content', async () => {
    const backup = (await call('select public_catalog_manifest() as m'))[0].m.version;
    const preview = (await call('select preview_catalog() as p'))[0].p;
    const active = (await call('select publish_catalog($1,$2) as version', [preview.revision, preview.sha256]))[0].version;
    const withdraw = (replacement: string | null, user = admin) =>
        call('select withdraw_catalog($1,$2,$3)', [active, 'Internal detail', replacement], user);
    await expect(withdraw(backup, editor)).rejects.toThrow();
    await expect(withdraw(null)).rejects.toThrow();
    await withdraw(backup);
    const manifest = (await call('select public_catalog_status($1::uuid[]) as m', [[active]], outsider, 'aal1', 'anon'))[0].m;
    expect(manifest.version).toBe(backup);
    expect(manifest.withdrawnVersions).toEqual([active]);
    expect(JSON.stringify(manifest)).not.toContain('Internal detail');
    expect((await call('select public_catalog_content($1) as content', [active], outsider, 'aal1', 'anon'))[0].content).toBeNull();
    await expect(call('select restore_catalog($1)', [active])).rejects.toThrow();
});

test('publication rejects invalid civil dates', async () => {
    const baseline = (await call('select preview_catalog() as p'))[0].p;
    const invalid = structuredClone(document);
    invalid.features[0].publicFields.push(
        { category: 'updated-at', label: 'Fecha', value: '2026-02-30', evidence: '', secret: '' },
    );
    await call('select save_catalog($1,$2)', [invalid, baseline.revision]);
    const next = (await call('select preview_catalog() as p'))[0].p;
    await expect(call('select publish_catalog($1,$2)', [next.revision, next.sha256])).rejects.toThrow();
    await call('select save_catalog($1,$2)', [document, next.revision]);
});
