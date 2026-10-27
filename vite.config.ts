import { defineConfig } from 'vitest/config';
export default defineConfig({
  test: { projects: [
    {test:{name:'data',include:['tests/backend.test.ts','tests/catalog.test.ts'],environment:'node'}},
    {test:{name:'panel',include:['tests/panel.test.tsx'],environment:'jsdom'}}
  ] },
  server: { host:'127.0.0.1',port:5173,strictPort:true,fs:{allow:['..']},headers:{'X-Frame-Options':'DENY','Referrer-Policy':'no-referrer','Content-Security-Policy':"frame-ancestors 'none'; object-src 'none'; base-uri 'none'"} },
});
