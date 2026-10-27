import { readFile, writeFile } from 'node:fs/promises';
import { createHash, randomBytes, randomUUID } from 'node:crypto';
import assert from 'node:assert/strict';
import { createClient } from '@supabase/supabase-js';
import { TOTP } from 'otpauth';
const env = Object.fromEntries(
    (await readFile('local-data/supabase.env', 'utf8'))
        .split(/\r?\n/)
        .filter((v) => v.includes('='))
        .map((v) => {
            const i = v.indexOf('=');
            return [v.slice(0, i), v.slice(i + 1).replace(/^"|"$/g, '')];
        }),
);
const url = 'http://127.0.0.1:54321',
    options = { auth: { persistSession: false, autoRefreshToken: false } };
const root = createClient(url, env.SERVICE_ROLE_KEY, options),
    anonymous = createClient(url, env.PUBLISHABLE_KEY || env.ANON_KEY, options);
const signup = await anonymous.auth.signUp({
    email: 'signup@rutastijuana.local',
    password: randomBytes(24).toString('base64url'),
});
assert(signup.error);
const before = await root.from('catalog_drafts').select('revision,document').eq('id', 1).single();
assert.ifError(before.error);
if (before.data.document.features.some((f) => f.id !== 'example-route'))
    throw Error('La prueba requiere un catálogo vacío o el ejemplo local.');
const identity = [];
for (const role of ['admin', 'editor']) {
    const email = `qa-${role}-${randomUUID().slice(0, 8)}@rutastijuana.local`,
        password = randomBytes(24).toString('base64url');
    const created = await root.auth.admin.createUser({ email, password, email_confirm: true });
    assert.ifError(created.error);
    const userID = created.data.user.id;
    assert.ifError((await root.from('catalog_members').insert({ user_id: userID, role })).error);
    const client = createClient(url, env.PUBLISHABLE_KEY || env.ANON_KEY, options);
    assert.ifError((await client.auth.signInWithPassword({ email, password })).error);
    assert.equal((await client.rpc('catalog_role')).data, null);
    const factor = await client.auth.mfa.enroll({
        factorType: 'totp',
        friendlyName: 'Prueba local',
    });
    assert.ifError(factor.error);
    const secret = factor.data.totp.secret;
    const code = new TOTP({ secret, algorithm: 'SHA1', digits: 6, period: 30 }).generate();
    assert.ifError(
        (await client.auth.mfa.challengeAndVerify({ factorId: factor.data.id, code })).error,
    );
    assert.equal((await client.rpc('catalog_role')).data, role);
    identity.push({ userID, email, password, secret, role, client });
}
const [admin, editor] = identity;
const doc = {
    groups: [{ id: 'example-group', name: 'Ejemplo' }],
    features: [
        {
            id: 'example-route',
            name: 'Recorrido de ejemplo',
            groupID: 'example-group',
            kind: 'route',
            color: '#2476E8',
            included: true,
            geometry: {
                type: 'LineString',
                coordinates: [
                    [-117.02, 32.525],
                    [-117.02, 32.531],
                    [-117.015, 32.537],
                    [-117.005, 32.537],
                ],
            },
            publicDescription: 'Recorrido de ejemplo para la consulta local.',
            publicFields: [
                { category: 'schedule', label: 'Horario', value: '06:00–20:00' },
                { category: 'fare', label: 'Tarifa', value: '$9' },
            ],
            privateNotes: 'PRIVATE_NOTE',
            source: { description: 'PRIVATE_SOURCE' },
        },
    ],
};
const saved = await editor.client.rpc('save_catalog', {
    d: doc,
    expected_revision: before.data.revision,
});
assert.ifError(saved.error);
assert(
    (await editor.client.rpc('save_catalog', { d: doc, expected_revision: before.data.revision }))
        .error,
);
assert((await editor.client.rpc('preview_catalog')).error);
const preview = await admin.client.rpc('preview_catalog');
assert.ifError(preview.error);
assert(!preview.data.payload.includes('PRIVATE_'));
assert(
    (
        await editor.client.rpc('publish_catalog', {
            expected_revision: saved.data,
            expected_hash: preview.data.sha256,
        })
    ).error,
);
const published = await admin.client.rpc('publish_catalog', {
    expected_revision: saved.data,
    expected_hash: preview.data.sha256,
});
assert.ifError(published.error);
const manifestResponse = await fetch(url + '/functions/v1/catalog');
assert.equal(manifestResponse.status, 200);
const manifest = await manifestResponse.json();
assert.equal(manifest.version, published.data);
const response = await fetch(new URL(manifest.downloadURL, url + '/functions/v1/catalog'));
assert.equal(response.status, 200);
const payload = Buffer.from(await response.arrayBuffer());
assert.equal(payload.length, manifest.bytes);
assert.equal(createHash('sha256').update(payload).digest('hex'), manifest.sha256);
assert(!payload.toString().includes('PRIVATE_'));
assert.equal((await fetch(url + '/functions/v1/catalog', { method: 'POST' })).status, 405);
const backup = await admin.client.rpc('catalog_backup');
assert.ifError(backup.error);
assert.deepEqual(backup.data.document, doc);
await writeFile(
    'local-data/qa-access.json',
    JSON.stringify(
        {
            users: identity.map(({ client, ...v }) => v),
            before: before.data,
            published: published.data,
        },
        null,
        2,
    ),
    { mode: 0o600 },
);
console.log(
    'Prueba local correcta: doble factor, permisos, concurrencia, publicación, descarga y respaldo.',
);
