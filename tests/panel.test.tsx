import React from 'react';
import { afterEach, expect, test, vi } from 'vitest';
import { cleanup, render, screen, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { Editor } from '../admin/src/Editor';
import type { CatalogAPI } from '../admin/src/api';
import type { Document } from '../shared/catalog';
afterEach(cleanup);
function service(role:'admin'|'editor'):CatalogAPI {
 let document:Document={groups:[{id:'g',name:'Ejemplo'}],features:[{id:'f',name:'Lugar de ejemplo',groupID:'g',kind:'reference',color:'#2476E8',geometry:{type:'Point',coordinates:[-117,32.5]},included:false,publicDescription:'',publicFields:[],privateNotes:'PRIVATE_NOTE',source:{description:'PRIVATE_SOURCE'}}]};
 let revision=0;
 return {
  role:async()=>role,draft:async()=>({revision,document}),
  save:vi.fn(async(d,r)=>{if(r!==revision)throw Error('Conflicto');document=d;return ++revision;}),
  preview:vi.fn(async()=>({revision,sha256:'a'.repeat(64),payload:JSON.stringify({schemaVersion:2,version:'preview',groups:document.groups,features:document.features.filter(f=>f.included).map(f=>({name:f.name,description:f.publicDescription}))})})),
  publish:vi.fn(async()=> 'version'),versions:async()=>[],audit:async()=>[],restore:async()=>{},backup:async()=>({document}),invite:async()=>{},members:async()=>[],revoke:async()=>{}
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
