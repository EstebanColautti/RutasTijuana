export type Geometry = { type: 'Point' | 'LineString' | 'MultiLineString' | 'Polygon' | 'MultiPolygon'; coordinates: unknown };
export type Field = { category: string; label: string; value: string };
export type Feature = { id: string; name: string; groupID: string; kind: 'route' | 'area' | 'reference' | 'stop'; color: string; geometry: Geometry; included: boolean; publicDescription: string; publicFields: Field[]; privateNotes?: string; source?: unknown };
export type Document = { groups: { id: string; name: string }[]; features: Feature[] };
export type Draft = { revision: number; document: Document; updated_at?: string; updated_by?: string };
export type Preview = { revision: number; sha256: string; payload: string };
export type Version = { version: string; sha256: string; bytes: number; created_at: string; created_by: string };
export type Audit = { id: number; actor: string; action: string; revision?: number; version?: string; created_at: string };
export function validGeometry(g: unknown): g is Geometry {
  if (!g || typeof g !== 'object') return false;
  const { type, coordinates: c } = g as Geometry;
  if (!Array.isArray(c) || c.length === 0) return false;
  if (type === 'Point') return [2,3].includes(c.length) && c.every(n => typeof n === 'number' && Number.isFinite(n)) && Math.abs(c[0]) <= 180 && Math.abs(c[1]) <= 90;
  if (type === 'LineString') return c.length >= 2 && c.every(p => validGeometry({ type: 'Point', coordinates: p }));
  if (type === 'Polygon') return c.every(r => Array.isArray(r) && r.length >= 4 && JSON.stringify(r[0]) === JSON.stringify(r.at(-1)) && validGeometry({ type: 'LineString', coordinates: r }));
  if (type === 'MultiLineString' || type === 'MultiPolygon') return c.every(p => validGeometry({ type: type === 'MultiLineString' ? 'LineString' : 'Polygon', coordinates: p }));
  return false;
}
export function parseDocument(value: unknown): Document {
  if (!value || typeof value !== 'object') throw new Error('Formato incorrecto.');
  const d = value as Document;
  if (!Array.isArray(d.groups) || !Array.isArray(d.features) || d.features.length > 10000) throw new Error('Formato incorrecto.');
  const groups = new Set<string>(), ids = new Set<string>();
  for (const g of d.groups) {
    if (!g || typeof g.id !== 'string' || !g.id || typeof g.name !== 'string' || !g.name.trim() || groups.has(g.id)) throw new Error('Revisa los grupos.');
    groups.add(g.id);
  }
  for (const f of d.features) {
    if (!f || typeof f.id !== 'string' || !f.id || ids.has(f.id) || typeof f.name !== 'string' || !f.name.trim() || !groups.has(f.groupID) || !['route','area','reference','stop'].includes(f.kind) || !/^#[\da-f]{6}$/i.test(f.color) || typeof f.included !== 'boolean' || typeof f.publicDescription !== 'string' || !Array.isArray(f.publicFields) || f.publicFields.some(v => !v || ['category','label','value'].some(k => typeof v[k as keyof Field] !== 'string')) || !validGeometry(f.geometry)) throw new Error('Revisa los elementos del catálogo.');
    if (f.kind === 'route' && !['LineString','MultiLineString'].includes(f.geometry.type) || f.kind === 'stop' && f.geometry.type !== 'Point') throw new Error('La geometría no corresponde al tipo de elemento.');
    ids.add(f.id);
  }
  return d;
}
export function importCatalog(text: string): Document {
  if (new TextEncoder().encode(text).length > 16 * 1024 * 1024) throw new Error('El archivo supera 16 MB.');
  const raw = JSON.parse(text);
  if (raw.backupVersion === 1) return parseDocument(raw.document);
  if (raw.schemaVersion === 1 || raw.schemaVersion === 2) {
    return parseDocument({ groups: raw.groups, features: raw.features.map((f: Record<string, unknown>) => ({
      id: f.id, name: f.name, groupID: f.groupID, kind: f.kind, color: f.color, geometry: f.geometry,
      included: false, publicDescription: '', publicFields: [], privateNotes: '', source: f.information ?? null,
    })) });
  }
  return parseDocument(raw);
}
export function geometryPoints(g: Geometry): number[][] {
  switch (g.type) {
    case 'Point': return [g.coordinates as number[]];
    case 'LineString': return g.coordinates as number[][];
    case 'MultiLineString': case 'Polygon': return (g.coordinates as number[][][]).flat();
    case 'MultiPolygon': return (g.coordinates as number[][][][]).flat(2);
  }
}
