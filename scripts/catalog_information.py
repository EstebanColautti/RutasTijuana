import json
import re
from collections import defaultdict
from html.parser import HTMLParser


class PlainText(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.parts = []

    def handle_data(self, data):
        self.parts.append(data)

    def handle_starttag(self, tag, attrs):
        if tag in ('br', 'p', 'div', 'li'):
            self.parts.append('\n')


def plain(value):
    parser = PlainText()
    parser.feed(str(value or ''))
    return ''.join(parser.parts).strip()


def json_lines(path):
    if not path.exists():
        return []
    return [json.loads(line) for line in path.read_text(encoding='utf-8-sig').splitlines() if line.strip()]


def information_index(root):
    directory = root / 'data/intermediate'
    sources = {row['feature_id']: row for row in json_lines(directory / 'source_features.jsonl')}
    facts = defaultdict(list)
    for row in json_lines(root / 'data/processed/facts.jsonl'):
        facts[row['entity_id']].append(row)
    observations = defaultdict(list)
    for row in json_lines(directory / 'all_source_observations.jsonl'):
        key = (row.get('layer_name_raw', '').strip(), row.get('name_raw'),
               json.dumps(row.get('geometry'), sort_keys=True, separators=(',', ':')))
        observations[key].append(row)
    return sources, facts, observations


def build_information(feature, group_name, index):
    sources, facts, observations = index
    props = feature.get('properties') or {}
    source = sources.get(feature['id'], {})
    description = source.get('description_text') or plain(props.get('description'))
    rows = []

    def add(category, label, value, evidence='', inferred=False):
        if value is None or value == '':
            return
        if not isinstance(value, str):
            value = json.dumps(value, ensure_ascii=False, sort_keys=True)
        row = dict(category=category, label=label, value=value, evidence=evidence, inferred=inferred)
        if row not in rows:
            rows.append(row)

    labels = {'service_hours_text': ('schedule', 'Horario mencionado'),
              'fare_claim': ('fare', 'Tarifa mencionada'),
              'destination_text': ('places', 'Destinos mencionados'),
              'route_references_text': ('places', 'Rutas mencionadas'),
              'direction_label': ('direction', 'Sentido mencionado'),
              'contact_text': ('contact', 'Contacto mencionado'),
              'source_attribute': ('attribute', 'Dato adicional')}
    for fact in facts.get(feature['id'], []):
        if fact['field'] in labels:
            category, label = labels[fact['field']]
            evidence = fact.get('raw_evidence')
            evidence = evidence if isinstance(evidence, str) else json.dumps(evidence, ensure_ascii=False, sort_keys=True)
            value = evidence if fact['field'] == 'fare_claim' else fact.get('value')
            add(category, label, value, evidence)
    text = description or ''
    for line in text.splitlines():
        for category, label, pattern in [
            ('schedule', 'Horario o salida mencionada', r'horari|salidas?|regreso|\d\s*(?:a\.?\s*m\.?|p\.?\s*m\.?)'),
            ('fare', 'Detalle de tarifa', r'tarifa|estudiantes?|\$|pesos'),
            ('places', 'Lugares, bases o referencias', r'destinos?|bases?|terminal|sitio|desde|pasando|alimentadora'),
            ('note', 'Nota de operación', r'pendiente|puede cambiar|exclusivo|docentes|confirmar')]:
            if re.search(pattern, line, re.I):
                add(category, label, line, line)
    name = str(props.get('name') or '')
    code = re.search(r'\b(R\d+[A-Za-z]?)\s*:', name, re.I)
    if code:
        add('name', 'Código en el nombre', code.group(1), name)
    components = [v.strip() for v in re.split(r'(?<!\d)[-–→]|[-–→](?!\d)', re.sub(r'^\s*R\d+[A-Za-z]?\s*:\s*', '', name, flags=re.I)) if v.strip()]
    if len(components) >= 2:
        add('places', 'Referencias separadas del nombre', ' · '.join(components), name, True)
    for match in re.finditer(r'\b(?:ida|vuelta|regreso)\b', name, re.I):
        add('direction', 'Mención de sentido', match.group(), name + '\n' + text)
    add('attribute', 'Clasificación del elemento', props.get('classification'))
    for attribute in source.get('extended_data', []):
        add('attribute', str(attribute.get('display_name') or attribute.get('name') or 'Campo adicional'),
            attribute.get('value', attribute))
    for key in ('operational_status', 'verification_status', 'licensing_status'):
        add('status', {'operational_status': 'Estado de operación', 'verification_status': 'Verificación',
                      'licensing_status': 'Estado de uso'}[key], props.get(key))
    metrics = source.get('geometry_metrics') or {}
    metric_labels = {'length_m': 'Longitud geométrica (m)', 'vertex_count': 'Vértices',
                     'part_count': 'Partes', 'bbox': 'Límites [oeste, sur, este, norte]',
                     'first_vertex': 'Primer vértice',
                     'last_vertex': 'Último vértice',
                     'closed_parts': 'Partes cerradas', 'max_segment_m': 'Mayor segmento (m)'}
    for key, label in metric_labels.items():
        add('geometry', label, metrics.get(key), inferred=True)
    for warning in source.get('conversion_warnings', []):
        add('note', 'Revisión de geometría', warning, inferred=True)
    key = (group_name.strip(), source.get('name_raw', name),
           json.dumps(feature.get('geometry'), sort_keys=True, separators=(',', ':')))
    variants = observations.get(key, [])
    for alternate in variants:
        alternate_text = alternate.get('description_text', '')
        if alternate_text and alternate_text != description:
            add('note', 'Otra descripción disponible', alternate_text, alternate_text)
    media = set()
    for record in [source] + variants:
        raw = (record.get('description_raw') or '') + '\n' + '\n'.join(str(item.get('value') or '') for item in record.get('extended_data', []))
        media.update(re.findall(r'https?://[^\s<>"\x27]+', raw))
    for url in sorted(media):
        add('media', 'Enlace adjunto; sin descargar', url)
    return dict(description=description, fields=rows)
