import React from 'react';
import { afterEach, expect, test, vi } from 'vitest';
import { cleanup, fireEvent, render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { Editor } from '../admin/src/Editor';
import type { CatalogAPI } from '../admin/src/api';
import { publicationIssues, type Document } from '../shared/catalog';
afterEach(cleanup);
function service(role:'admin'|'editor'):CatalogAPI {
 let document:Document={groups:[{id:'g',name:'Ejemplo'}],features:[{id:'f',name:'Lugar de ejemplo',groupID:'g',kind:'reference',color:'#2476E8',geometry:{type:'Point',coordinates:[-117,32.5]},included:false,publicDescription:'',publicFields:[],privateNotes:'PRIVATE_NOTE',source:{description:'PRIVATE_SOURCE'}}]};
 let revision=0;
 return {
  role:async()=>role,draft:async()=>({revision,document}),
  save:vi.fn(async(d,r)=>{if(r!==revision)throw Error('Conflicto');document=d;return ++revision;}),
  preview:vi.fn(async()=>({revision,sha256:'a'.repeat(64),payload:JSON.stringify({schemaVersion:2,version:'preview',groups:document.groups,features:document.features.filter(f=>f.included).map(f=>({name:f.name,description:f.publicDescription}))})})),
  publish:vi.fn(async()=> 'version'),versions:async()=>[],audit:async()=>[],restore:async()=>{},withdraw:async()=>{},backup:async()=>({document}),invite:async()=>{},members:async()=>[],revoke:async()=>{}
 };
}
test('editor can save changes but has no publication controls',async()=>{
 const api=service('editor'),user=userEvent.setup();render(<Editor service={api} onSignOut={()=>{}}/>);
 await user.click(await screen.findByRole('button',{name:/Lugar de ejemplo/}));
 await user.type(screen.getByLabelText('Descripción pública'),'Descripción editada');
 await user.click(screen.getByRole('button',{name:'Guardar cambios'}));
 await screen.findByText('Cambios guardados.');expect(api.save).toHaveBeenCalled();expect(screen.queryByRole('button',{name:'Preparar publicación'})).toBeNull();
});
test('admin previews only selected public content and confirms publication',async()=>{
 const api=service('admin'),user=userEvent.setup();render(<Editor service={api} onSignOut={()=>{}}/>);
 await user.click(await screen.findByRole('button',{name:/Lugar de ejemplo/}));
 expect((screen.getByLabelText('Incluir en publicación') as HTMLInputElement).checked).toBe(false);
 await user.click(screen.getByLabelText('Incluir en publicación'));
 await user.type(screen.getByLabelText('Descripción pública'),'Descripción pública de ejemplo');
 await user.click(screen.getByRole('button',{name:'Guardar cambios'}));await screen.findByText('Cambios guardados.');
 await user.click(screen.getByRole('button',{name:'Preparar publicación'}));
 await screen.findByRole('heading',{name:'Contenido de la publicación'});
 const preview=screen.getByText(/"schemaVersion"/);expect(preview.textContent).not.toContain('PRIVATE_');expect(preview.textContent).toContain('Descripción pública de ejemplo');
 expect(api.publish).not.toHaveBeenCalled();await user.click(screen.getByRole('button',{name:'Publicar esta versión'}));await screen.findByText('Publicación disponible.');expect(api.publish).toHaveBeenCalledOnce();
});

test('a delayed save locks edits and keeps the draft on conflict', async () => {
 const api = service('editor'), user = userEvent.setup();
 let fail!: (error: Error) => void;
 api.save = vi.fn(() => new Promise<number>((_, reject) => { fail = reject; }));
 render(<Editor service={api} onSignOut={()=>{}}/>);
 await user.click(await screen.findByRole('button', { name: /Lugar de ejemplo/ }));
 const description = screen.getByLabelText('Descripción pública') as HTMLTextAreaElement;
 await user.type(description, 'Mi edición');
 await user.click(screen.getByRole('button', { name: 'Guardar cambios' }));
 expect(description.closest('[inert]')).not.toBeNull();
 fireEvent.change(description, { target: { value: 'Cambio tardío' } });
 fail(Error('Conflicto'));
 await screen.findByText('Conflicto');
 expect(description.value).toBe('Mi edición');
 expect(screen.getByRole('button', { name: 'Descargar borrador' })).toBeTruthy();
});

test('an editor reorders published stops without changing their identifiers', async () => {
 const api = service('editor'), user = userEvent.setup();
 const point = (id: string): Document['features'][number] => ({
   id, name: id, groupID: 'g', kind: 'stop', color: '#2476E8', included: true,
   geometry: { type: 'Point', coordinates: [-117, 32.5] }, publicDescription: '', publicFields: [],
 });
 const route: Document['features'][number] = {
   ...point('route'), kind: 'route', name: 'Ruta de prueba',
   geometry: { type: 'LineString', coordinates: [[-117, 32.5], [-117.01, 32.51]] },
   publicFields: [
     { category: 'route-shape', label: 'Tipo', value: 'linear' },
     { category: 'stop-order', label: 'Orden', value: '["one","two"]' },
   ],
 };
 api.draft = async () => ({ revision: 0, document: { groups: [{ id: 'g', name: 'Ejemplo' }], features: [route, point('one'), point('two')] } });
 api.save = vi.fn(async () => 1);
 render(<Editor service={api} onSignOut={() => {}} />);
 await user.click(await screen.findByRole('button', { name: /Ruta de prueba/ }));
 await user.click(screen.getByRole('button', { name: 'Bajar parada 1' }));
 await user.click(screen.getByRole('button', { name: 'Guardar cambios' }));
 await screen.findByText('Cambios guardados.');
 const saved = vi.mocked(api.save).mock.calls[0][0];
 expect(saved.features.find((feature) => feature.id === 'route')?.publicFields.find((field) => field.category === 'stop-order')?.value).toBe('["two","one"]');
 expect(saved.features.map((feature) => feature.id)).toEqual(['route','one','two']);
});

test('publication preflight rejects excluded stops, ambiguous contacts and impossible dates', () => {
 const feature: Document['features'][number] = { id:'r', name:'Route', groupID:'g', kind:'route', color:'#2476E8', included:true,
 geometry:{type:'LineString',coordinates:[[-117,32.5],[-117.01,32.51]]},publicDescription:'',publicFields:[
 {category:'stop-order',label:'Orden',value:'["one","two"]'},
 {category:'route-shape',label:'Tipo',value:'linear'},
 {category:'updated-at',label:'Fecha',value:'2026-02-30'}]};
 const document:Document={groups:[{id:'g',name:'Example'}],features:[feature]};
 expect(publicationIssues(document)).toHaveLength(2);
 const contact = { ...feature, kind:'reference' as const, publicFields:[
 {category:'service-role',label:'Servicio',value:'contact'},
 {category:'contact',label:'Contacto',value:'https://example.test'}]};
 document.features=[contact,{...contact,id:'other'}];
 expect(publicationIssues(document)).toEqual(['Conserva un único contacto oficial.']);
 document.features=[contact];
 expect(publicationIssues(document)).toEqual([]);
});
