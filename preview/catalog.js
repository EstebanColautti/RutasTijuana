(function (scope) {
  'use strict';
  const fold = value => value.normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLocaleLowerCase('es-MX');
  const lineParts = geometry => geometry.type === 'LineString' ? [geometry.coordinates] : geometry.type === 'MultiLineString' ? geometry.coordinates : [];
  const polygonParts = geometry => geometry.type === 'Polygon' ? [geometry.coordinates] : geometry.type === 'MultiPolygon' ? geometry.coordinates : [];
  const positions = geometry => geometry.type === 'Point' ? [geometry.coordinates] : [...lineParts(geometry).flat(), ...polygonParts(geometry).flat(2)];

  function parse(text) {
    if (new TextEncoder().encode(text).length > 16 * 1024 * 1024) throw new Error('El catálogo supera el tamaño permitido.');
    const data = JSON.parse(text);
    if (data.schemaVersion !== 1 || !Array.isArray(data.groups) || !Array.isArray(data.features) || data.features.length > 10000) throw new Error('El formato del catálogo no es compatible.');
    const ids = new Set(), groups = new Set();
    for (const group of data.groups) {
      if (typeof group.id !== 'string' || !group.id || typeof group.name !== 'string' || !group.name || groups.has(group.id)) throw new Error('Los grupos no son válidos.');
      groups.add(group.id);
    }
    for (const feature of data.features) {
      if (typeof feature.id !== 'string' || !feature.id || ids.has(feature.id) || typeof feature.name !== 'string' || !feature.name || !groups.has(feature.groupID)) throw new Error('Los identificadores o referencias no son válidos.');
      ids.add(feature.id);
      if (feature.information != null && (typeof feature.information.description !== 'string' || !Array.isArray(feature.information.fields) || feature.information.fields.some(f => !f || ['category', 'label', 'value', 'evidence'].some(k => typeof f[k] !== 'string') || typeof f.inferred !== 'boolean'))) throw new Error('La información del catálogo no es compatible.');
      if (!['route', 'area', 'reference'].includes(feature.kind) || !feature.geometry || !['Point', 'LineString', 'MultiLineString', 'Polygon', 'MultiPolygon'].includes(feature.geometry.type)) throw new Error('La geometría no es compatible.');
      const points = positions(feature.geometry);
      if (!points.length || points.some(p => !Array.isArray(p) || ![2, 3].includes(p.length) || p.some(n => typeof n !== 'number' || !Number.isFinite(n)) || Math.abs(p[0]) > 180 || Math.abs(p[1]) > 90)) throw new Error('Las coordenadas no son válidas.');
      if (lineParts(feature.geometry).some(p => p.length < 2) || (feature.kind === 'route' && !lineParts(feature.geometry).length)) throw new Error('El recorrido no contiene una línea válida.');
      if (polygonParts(feature.geometry).some(p => !p.length || p.some(r => r.length < 4 || JSON.stringify(r[0]) !== JSON.stringify(r.at(-1))))) throw new Error('Un polígono no está cerrado.');
    }
    return data;
  }

  function search(data, query, groupID = '', routesOnly = true) {
    const names = new Map(data.groups.map(g => [g.id, g.name]));
    const terms = fold(query).trim().split(/\s+/).filter(Boolean);
    return data.features.filter(f => (!routesOnly || f.kind === 'route') && (!groupID || f.groupID === groupID) && terms.every(t => fold(f.name + ' ' + names.get(f.groupID) + ' ' + (f.information ? f.information.description + ' ' + f.information.fields.map(v => v.label + ' ' + v.value).join(' ') : '')).includes(t)))
      .sort((a, b) => a.name.localeCompare(b.name, 'es', { numeric: true }) || a.id.localeCompare(b.id));
  }

  function distance(a, b) {
    const scale = Math.PI / 180, deltaLat = (b[1] - a[1]) * scale, deltaLon = (b[0] - a[0]) * scale;
    return 6371000 * 2 * Math.asin(Math.sqrt(Math.min(1, Math.sin(deltaLat / 2) ** 2 + Math.cos(a[1] * scale) * Math.cos(b[1] * scale) * Math.sin(deltaLon / 2) ** 2)));
  }

  function bearing(a, b) {
    const s = Math.PI / 180, delta = (b[0] - a[0]) * s;
    return Math.atan2(Math.sin(delta) * Math.cos(b[1] * s), Math.cos(a[1] * s) * Math.sin(b[1] * s) - Math.sin(a[1] * s) * Math.cos(b[1] * s) * Math.cos(delta));
  }

  function segmentDistance(point, a, b) {
    const length = distance(a, b) / 6371000;
    if (length < 1e-12) return distance(point, a);
    const angle = distance(a, point) / 6371000, difference = bearing(a, point) - bearing(a, b);
    const along = Math.atan2(Math.sin(angle) * Math.cos(difference), Math.cos(angle));
    if (along < 0 || along > length) return Math.min(distance(point, a), distance(point, b));
    return Math.abs(Math.asin(Math.max(-1, Math.min(1, Math.sin(angle) * Math.sin(difference))))) * 6371000;
  }

  function nearby(feature, point) {
    if (feature.kind !== 'route') return null;
    const distances = lineParts(feature.geometry).flatMap(line => line.slice(1).map((end, i) => segmentDistance(point, line[i], end)));
    return distances.length ? Math.min(...distances) : null;
  }

  const api = { parse, search, lineParts, polygonParts, positions, nearby };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  else scope.catalogModel = api;
})(typeof window === 'undefined' ? this : window);
