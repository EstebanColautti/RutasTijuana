type Handler = (request: Request) => Promise<Response>;
const handlers: Handler[] = [];
const original = Deno.serve;
Object.defineProperty(Deno, 'serve', { value: (handler: Handler) => handlers.push(handler), configurable: true });
try {
    await import('../supabase/functions/catalog/index.ts');
    await import('../supabase/functions/team/index.ts');
} finally {
    Object.defineProperty(Deno, 'serve', { value: original, configurable: true });
}
function equal(actual: unknown, expected: unknown) {
    if (actual !== expected) throw new Error('Respuesta incorrecta: ' + actual + ' != ' + expected);
}
Deno.test('public endpoint rejects invalid methods and version parameters before accessing data', async () => {
    const catalog = handlers[0];
    equal((await catalog(new Request('https://example.test/catalog', { method: 'OPTIONS' }))).status, 200);
    equal((await catalog(new Request('https://example.test/catalog', { method: 'POST' }))).status, 405);
    equal((await catalog(new Request('https://example.test/catalog?version=invalid'))).status, 400);
    equal((await catalog(new Request('https://example.test/catalog?cached=invalid'))).status, 400);
    equal((await catalog(new Request('https://example.test/catalog?asset=invalid'))).status, 400);
    const response = await catalog(new Request('https://example.test/catalog?version=invalid'));
    equal(response.headers.get('Cache-Control'), 'no-store');
});
Deno.test('team endpoint enforces origin and authentication before processing invitations', async () => {
    const team = handlers[1];
    equal((await team(new Request('https://example.test/team', { method: 'POST' }))).status, 403);
    const headers = { origin: 'http://127.0.0.1:5173' };
    equal((await team(new Request('https://example.test/team', { method: 'OPTIONS', headers }))).status, 200);
    equal((await team(new Request('https://example.test/team', { headers }))).status, 405);
    equal((await team(new Request('https://example.test/team', { method: 'POST', headers }))).status, 401);
});
