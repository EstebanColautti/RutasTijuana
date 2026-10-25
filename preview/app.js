'use strict';
const model = window.catalogModel, $ = id => document.getElementById(id);
let catalog = null, selected = null, reference = null, bounds = null, visible = [], distances = new Map();
const canvas = $('map'), context = canvas.getContext('2d');
function openFile() { $('file').click(); }
$('open').onclick = openFile; $('open-empty').onclick = openFile;
$('file').onchange = async event => {
  const file = event.target.files[0];
  if (!file) return;
  try {
    if (file.size > 16 * 1024 * 1024) throw new Error('El catálogo supera el tamaño permitido.');
    const decoded = model.parse(await file.text());
    catalog = decoded; selected = null; reference = null; bounds = null;
    $('search').value = ''; $('routes').checked = true; $('group').replaceChildren();
    const all = document.createElement('option'); all.value = ''; all.textContent = 'Todos los grupos'; $('group').append(all);
    for (const group of catalog.groups) { const option = document.createElement('option'); option.value = group.id; option.textContent = group.name; $('group').append(option); }
    $('notice').hidden = catalog.publishable && catalog.licenseStatus === 'verified';
    $('empty').hidden = true; $('layout').hidden = false; $('error').hidden = true; render();
  } catch (error) { $('error').textContent = error.message; $('error').hidden = false; }
  event.target.value = '';
};
function fit(features) {
  const points = features.flatMap(f => model.positions(f.geometry));
  if (!points.length) return;
  const xs = points.map(p => p[0]), ys = points.map(p => p[1]);
  const x0 = Math.min(...xs), x1 = Math.max(...xs), y0 = Math.min(...ys), y1 = Math.max(...ys);
  const dx = Math.max(.004, x1 - x0) * .65, dy = Math.max(.004, y1 - y0) * .65;
  bounds = [(x0 + x1) / 2 - dx, (y0 + y1) / 2 - dy, (x0 + x1) / 2 + dx, (y0 + y1) / 2 + dy];
}
function render() {
  if (!catalog) return;
  visible = model.search(catalog, $('search').value, $('group').value, $('routes').checked);
  distances = new Map();
  if (reference) {
    visible = visible.filter(f => { const d = model.nearby(f, reference); if (d !== null) distances.set(f.id, d); return d !== null && d <= 1000; });
    visible.sort((a, b) => distances.get(a.id) - distances.get(b.id) || a.id.localeCompare(b.id));
  }
  if (!visible.some(f => f.id === selected)) selected = null;
  $('count').textContent = 'Resultados: ' + visible.length; $('clear').hidden = !reference;
  $('hint').textContent = $('routes').checked ? 'Toca el mapa para consultar trazados a 1 km' : 'Áreas y referencias; no son paradas confirmadas';
  $('list').replaceChildren();
  for (const feature of visible) {
    const row = document.createElement('button'); row.className = 'row' + (selected === feature.id ? ' selected' : '');
    const dot = document.createElement('span'); dot.className = 'dot'; dot.style.background = /^#[0-9a-f]{6}$/i.test(feature.color) ? feature.color : '#2476e8';
    const text = document.createElement('span'); text.textContent = feature.name;
    const category = document.createElement('small'); category.textContent = catalog.groups.find(g => g.id === feature.groupID).name; text.append(category);
    if (distances.has(feature.id)) { const d = document.createElement('small'); d.textContent = 'A ' + Math.round(distances.get(feature.id)) + ' m del trazado'; text.append(d); }
    row.append(dot, text); row.onclick = () => { selected = feature.id; fit([feature]); render(); }; $('list').append(row);
  }
  if (!visible.length) { const empty = document.createElement('p'); empty.textContent = 'Sin coincidencias. Cambia la búsqueda, el grupo o el punto de referencia.'; $('list').append(empty); }
  const feature = visible.find(f => f.id === selected); $('detail').hidden = !feature;
  if (feature) {
    $('name').textContent = feature.name;
    $('status').textContent = feature.kind === 'route' ? 'Recorrido de referencia · Sentido sin verificar' : 'Área de referencia · Ascenso y descenso sin verificar';
    $('schedule').textContent = feature.kind === 'route' ? 'Horario y frecuencia: dato no disponible' : '';
    $('distance-note').textContent = feature.kind === 'route' ? 'La cercanía al trazado no confirma dónde subir ni un camino peatonal.' : '';
  }
  if (!bounds) fit(visible);
  draw();
}
function draw() {
  const width = canvas.clientWidth, height = canvas.clientHeight, ratio = window.devicePixelRatio || 1;
  canvas.width = width * ratio; canvas.height = height * ratio; context.setTransform(ratio, 0, 0, ratio, 0, 0);
  context.fillStyle = '#f6f8fc'; context.fillRect(0, 0, width, height);
  if (!bounds) return;
  const dx = bounds[2] - bounds[0], dy = bounds[3] - bounds[1];
  const scale = Math.min((width - 50) / dx, (height - 50) / dy), ox = (width - dx * scale) / 2, oy = (height - dy * scale) / 2;
  const project = p => [ox + (p[0] - bounds[0]) * scale, height - oy - (p[1] - bounds[1]) * scale];
  canvas.unproject = p => [bounds[0] + (p[0] - ox) / scale, bounds[1] + (height - oy - p[1]) / scale];
  context.strokeStyle = '#e3e8f1'; context.lineWidth = 1;
  for (let i = 0; i <= 8; i++) { const x = width * i / 8; context.beginPath(); context.moveTo(x, 0); context.lineTo(x, height); context.stroke(); const y = height * i / 8; context.beginPath(); context.moveTo(0, y); context.lineTo(width, y); context.stroke(); }
  function path(points) { points.forEach((p, i) => { const v = project(p); if (i) context.lineTo(...v); else context.moveTo(...v); }); }
  for (const feature of [...visible.filter(f => f.id !== selected), ...visible.filter(f => f.id === selected)]) {
    const color = /^#[0-9a-f]{6}$/i.test(feature.color) ? feature.color : '#2476e8';
    context.strokeStyle = selected === feature.id ? '#da3481' : color; context.lineWidth = selected === feature.id ? 5 : 2.3;
    for (const line of model.lineParts(feature.geometry)) { context.beginPath(); path(line); context.stroke(); }
    for (const polygon of model.polygonParts(feature.geometry)) { context.beginPath(); for (const ring of polygon) { path(ring); context.closePath(); } context.fillStyle = color + '24'; context.fill('evenodd'); context.stroke(); }
    if (feature.geometry.type === 'Point') { const p = project(feature.geometry.coordinates); context.beginPath(); context.arc(...p, 4, 0, 2 * Math.PI); context.fillStyle = color; context.fill(); }
  }
  if (reference) { const p = project(reference); context.beginPath(); context.arc(...p, 7, 0, 2 * Math.PI); context.fillStyle = '#1763d6'; context.fill(); }
}
$('search').oninput = () => { selected = null; render(); };
$('group').onchange = () => { selected = null; bounds = null; render(); };
$('routes').onchange = () => { reference = null; selected = null; bounds = null; render(); };
$('clear').onclick = () => { reference = null; bounds = null; render(); };
$('fit').onclick = () => { bounds = null; render(); };
$('close').onclick = () => { selected = null; render(); };
canvas.onclick = event => { if (!$('routes').checked || !canvas.unproject) return; const rect = canvas.getBoundingClientRect(); reference = canvas.unproject([event.clientX - rect.left, event.clientY - rect.top]); selected = null; render(); };
new ResizeObserver(draw).observe(canvas);
