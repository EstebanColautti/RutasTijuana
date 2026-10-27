import { createClient } from 'npm:@supabase/supabase-js@2.118.0';
const headers = {
    'Content-Type': 'application/json; charset=utf-8',
    'Access-Control-Allow-Origin': '*',
    'X-Content-Type-Options': 'nosniff',
};
Deno.serve(async (request: Request) => {
    if (request.method === 'OPTIONS')
        return new Response(null, {
            headers: { ...headers, 'Access-Control-Allow-Methods': 'GET, OPTIONS' },
        });
    if (request.method !== 'GET') return new Response(null, { status: 405, headers });
    const url = new URL(request.url),
        version = url.searchParams.get('version');
    if (version && !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(version))
        return new Response(null, { status: 400, headers });
    const key =
        JSON.parse(Deno.env.get('SUPABASE_PUBLISHABLE_KEYS') || '{}').default ||
        Deno.env.get('SUPABASE_ANON_KEY');
    const client = createClient(Deno.env.get('SUPABASE_URL')!, key!, {
        auth: { persistSession: false },
    });
    const { data, error } = version
        ? await client.rpc('public_catalog_content', { v: version })
        : await client.rpc('public_catalog_manifest');
    if (error)
        return new Response(JSON.stringify({ error: 'Servicio no disponible.' }), {
            status: 503,
            headers,
        });
    if (!data) return new Response(null, { status: 404, headers });
    if (version)
        return new Response(data, {
            headers: { ...headers, 'Cache-Control': 'public, max-age=31536000, immutable' },
        });
    return new Response(
        JSON.stringify({
            ...data,
            downloadURL: '?version=' + data.version,
        }),
        { headers: { ...headers, 'Cache-Control': 'public, max-age=60' } },
    );
});
