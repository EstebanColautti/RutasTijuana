import { test, expect } from 'vitest';
import { importCatalog, parseDocument, validGeometry } from '../shared/catalog';
const feature={id:'f',name:'Ejemplo',groupID:'g',kind:'route',color:'#2476E8',geometry:{type:'LineString',coordinates:[[0,0],[1,1]]},information:{description:'SOURCE_TEXT',fields:[]}};
test('legacy import keeps the working data separate from publication',()=>{
 const d=importCatalog(JSON.stringify({schemaVersion:1,groups:[{id:'g',name:'Grupo'}],features:[feature]}));
 expect(d.features[0].included).toBe(false);expect(d.features[0].publicDescription).toBe('');expect(d.features[0].source).toEqual(feature.information);
 expect(importCatalog(JSON.stringify({backupVersion:1,document:d}))).toEqual(d);
});
test('preserves holes and rejects open rings, duplicate identifiers and arbitrary content',()=>{
 const geometry={type:'Polygon',coordinates:[[[0,0],[0,4],[4,4],[0,0]],[[1,1],[1,2],[2,2],[1,1]]]};
 expect(validGeometry(geometry)).toBe(true);expect(validGeometry({type:'Polygon',coordinates:[[[0,0],[1,1],[2,2],[3,3]]]})).toBe(false);
 const d=importCatalog(JSON.stringify({schemaVersion:1,groups:[{id:'g',name:'Grupo'}],features:[feature]}));
 expect(()=>parseDocument({...d,features:[...d.features,...d.features]})).toThrow();
});
