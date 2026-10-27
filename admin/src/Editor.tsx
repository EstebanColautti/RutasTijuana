import { useEffect, useRef, useState, type ChangeEvent } from 'react';
import {
    geometryPoints,
    importCatalog,
    parseDocument,
    validGeometry,
    type Audit,
    type Document,
    type Draft,
    type Feature,
    type Preview,
    type Version,
} from '../../shared/catalog';
import type { CatalogAPI } from './api';
export function GeometryPreview({ feature }: { feature?: Feature }) {
    if (!feature) return <div className="map empty">Selecciona un elemento</div>;
    const p = geometryPoints(feature.geometry),
        xs = p.map((p) => p[0]),
        ys = p.map((p) => p[1]);
    const west = Math.min(...xs),
        east = Math.max(...xs),
        south = Math.min(...ys),
        north = Math.max(...ys);
    const scale = Math.min(
        560 / Math.max(0.001, east - west),
        240 / Math.max(0.001, north - south),
    );
    const point = (p: number[]) =>
        `${300 + (p[0] - (west + east) / 2) * scale},${140 - (p[1] - (south + north) / 2) * scale}`;
    const c = feature.geometry.coordinates;
    const lines: number[][][] =
        feature.geometry.type === 'LineString'
            ? [c as number[][]]
            : feature.geometry.type === 'MultiLineString'
              ? (c as number[][][])
              : [];
    const polygons: number[][][][] =
        feature.geometry.type === 'Polygon'
            ? [c as number[][][]]
            : feature.geometry.type === 'MultiPolygon'
              ? (c as number[][][][])
              : [];
    return (
        <figure className="map">
            <svg viewBox="0 0 600 280" role="img" aria-label={'Trazado de ' + feature.name}>
                <defs>
                    <pattern id="grid" width="40" height="40" patternUnits="userSpaceOnUse">
                        <path d="M 40 0 L 0 0 0 40" fill="none" stroke="#e0e7ed" />
                    </pattern>
                </defs>
                <rect width="600" height="280" fill="url(#grid)" />
                {lines.map((l, i) => (
                    <polyline
                        key={i}
                        points={l.map(point).join(' ')}
                        fill="none"
                        stroke={feature.color}
                        strokeWidth="3"
                    />
                ))}
                {polygons.map((poly, i) => (
                    <path
                        key={i}
                        d={poly.map((r) => 'M' + r.map(point).join('L') + 'Z').join(' ')}
                        fill={feature.color + '25'}
                        fillRule="evenodd"
                        stroke={feature.color}
                        strokeWidth="2"
                    />
                ))}
                {feature.geometry.type === 'Point' && (
                    <circle
                        cx={point(feature.geometry.coordinates as number[]).split(',')[0]}
                        cy={point(feature.geometry.coordinates as number[]).split(',')[1]}
                        r="6"
                        fill={feature.color}
                    />
                )}
            </svg>
            <figcaption>
                {south.toFixed(4)}, {west.toFixed(4)} — {north.toFixed(4)}, {east.toFixed(4)}
            </figcaption>
        </figure>
    );
}
function download(name: string, data: unknown) {
    const url = URL.createObjectURL(
        new Blob([JSON.stringify(data, null, 2)], { type: 'application/json' }),
    );
    const a = document.createElement('a');
    a.href = url;
    a.download = name;
    a.click();
    URL.revokeObjectURL(url);
}
export function Editor({ service, onSignOut }: { service: CatalogAPI; onSignOut: () => unknown }) {
    const [draft, setDraft] = useState<Draft | null>(null),
        [role, setRole] = useState(''),
        [selection, setSelection] = useState(''),
        [search, setSearch] = useState(''),
        [message, setMessage] = useState(''),
        [busy, setBusy] = useState(false),
        [dirty, setDirty] = useState(false),
        [preview, setPreview] = useState<Preview | null>(null),
        [versions, setVersions] = useState<Version[]>([]),
        [audit, setAudit] = useState<Audit[]>([]),
        [email, setEmail] = useState('');
    const [members,setMembers]=useState<{user_id:string;role:string}[]>([]);
  const catalogInput = useRef<HTMLInputElement>(null),
        geoInput = useRef<HTMLInputElement>(null);
    const feature = draft?.document.features.find((f) => f.id === selection);
    async function load() {
        setBusy(true);
        try {
            const r = await service.role();
            setRole(r);
            const d = await service.draft();
            setDraft(d);
            setDirty(false);
            setPreview(null);
            setAudit(await service.audit());
            if (r === 'admin') { setVersions(await service.versions()); setMembers(await service.members()); }
            setMessage('');
        } catch (e) {
            setMessage((e as Error).message);
        } finally {
            setBusy(false);
        }
    }
    useEffect(() => {
        void load();
    }, []);
    useEffect(() => {
        const leave = (e: BeforeUnloadEvent) => {
            if (dirty) {
                e.preventDefault();
                e.returnValue = '';
            }
        };
        window.addEventListener('beforeunload', leave);
        return () => window.removeEventListener('beforeunload', leave);
    }, [dirty]);
    function updateDocument(d: Document) {
        setDraft((v) => (v ? { ...v, document: d } : v));
        setDirty(true);
        setPreview(null);
    }
    function patch(p: Partial<Feature>) {
        if (draft && feature)
            updateDocument({
                ...draft.document,
                features: draft.document.features.map((f) =>
                    f.id === feature.id ? { ...f, ...p } : f,
                ),
            });
    }
    async function run(action: () => Promise<void>) {
        setBusy(true);
        setMessage('');
        try {
            await action();
        } catch (e) {
            setMessage((e as Error).message);
        } finally {
            setBusy(false);
        }
    }
    async function save() {
        if (!draft) return;
        parseDocument(draft.document);
        const revision = await service.save(draft.document, draft.revision);
        setDraft({ ...draft, revision });
        setDirty(false);
        setPreview(null);
        setAudit(await service.audit());
        setMessage('Cambios guardados.');
    }
    async function importFile(e: ChangeEvent<HTMLInputElement>) {
        const file = e.target.files?.[0];
        if (!file) return;
        try {
            if (file.size > 16 * 1024 * 1024) throw Error('El archivo supera 16 MB.');
            updateDocument(importCatalog(await file.text()));
            setSelection('');
            setMessage('Archivo incorporado al borrador.');
        } catch (e) {
            setMessage((e as Error).message);
        }
        e.target.value = '';
    }
    async function importGeometry(e: ChangeEvent<HTMLInputElement>) {
        const file = e.target.files?.[0];
        if (!file || !draft) return;
        try {
            if (file.size > 16 * 1024 * 1024) throw Error('El archivo supera 16 MB.');
            const raw = JSON.parse(await file.text());
            if (feature) {
                const g = raw.type === 'Feature' ? raw.geometry : raw;
                if (!validGeometry(g)) throw Error('Geometría incorrecta.');
                patch({ geometry: g });
            } else {
                if (raw.type !== 'FeatureCollection' || !Array.isArray(raw.features))
                    throw Error('Selecciona un elemento o importa una colección GeoJSON.');
                let groups = [...draft.document.groups];
                const groupID = groups[0]?.id ?? crypto.randomUUID();
                if (!groups.length) groups = [{ id: groupID, name: 'Recorridos' }];
                const incoming: Feature[] = raw.features.map(
                    (
                        f: {
                            id?: string;
                            properties?: { name?: string };
                            geometry: Feature['geometry'];
                        },
                        i: number,
                    ) => ({
                        id: f.id || crypto.randomUUID(),
                        name: f.properties?.name || 'Elemento ' + (i + 1),
                        groupID,
                        kind: ['LineString', 'MultiLineString'].includes(f.geometry?.type)
                            ? 'route'
                            : f.geometry?.type === 'Point'
                              ? 'reference'
                              : 'area',
                        geometry: f.geometry,
                        color: '#2476E8',
                        included: false,
                        publicDescription: '',
                        publicFields: [],
                    }),
                );
                updateDocument(
                    parseDocument({ groups, features: [...draft.document.features, ...incoming] }),
                );
            }
            setMessage('Geometría incorporada al borrador.');
        } catch (e) {
            setMessage((e as Error).message);
        }
        e.target.value = '';
    }
    const source = feature?.source as {
        description?: string;
        fields?: { category: string; label: string; value: string }[];
    } | null;
    return (
        <>
            <header>
                <div>
                    <p className="eyebrow">RUTAS TIJUANA</p>
                    <h1>Catálogo</h1>
                </div>
                <div className="actions">
                    <span className="badge">{role === 'admin' ? 'Administrador' : 'Editor'}</span>
                    <button className="secondary" onClick={() => onSignOut()}>
                        Salir
                    </button>
                </div>
            </header>
            <main className="workspace">
                <nav className="actions">
                    <button disabled={busy || !dirty} onClick={() => void run(save)}>
                        Guardar cambios
                    </button>
                    <button
                        className="secondary"
                        disabled={busy}
                        onClick={() => {
                            if (!dirty || confirm('Se descartarán los cambios sin guardar.'))
                                void load();
                        }}
                    >
                        Recargar
                    </button>
                    <button
                        className="secondary"
                        disabled={busy}
                        onClick={() => {
                            if (!dirty || confirm('El archivo sustituirá el borrador sin guardar.'))
                                catalogInput.current?.click();
                        }}
                    >
                        Importar catálogo
                    </button>
                    <button
                        className="secondary"
                        disabled={busy}
                        onClick={() => geoInput.current?.click()}
                    >
                        Importar GeoJSON
                    </button>
                    {role === 'admin' && (
                        <>
                            <button
                                disabled={busy || dirty || !draft}
                                onClick={() =>
                                    void run(async () => setPreview(await service.preview()))
                                }
                            >
                                Preparar publicación
                            </button>
                            <button
                                className="secondary"
                                disabled={busy}
                                onClick={() =>
                                    void run(async () =>
                                        download('catalog-backup.json', await service.backup()),
                                    )
                                }
                            >
                                Exportar respaldo
                            </button>
                        </>
                    )}
                    <input
                        ref={catalogInput}
                        type="file"
                        accept=".json,application/json"
                        hidden
                        onChange={(e) => void importFile(e)}
                    />
                    <input
                        ref={geoInput}
                        type="file"
                        accept=".geojson,.json"
                        hidden
                        onChange={(e) => void importGeometry(e)}
                    />
                </nav>
                <p role="status" className="status">
                    {busy
                        ? 'Procesando…'
                        : message ||
                          (dirty ? 'Cambios sin guardar' : 'Revisión ' + (draft?.revision ?? '—'))}
                </p>
                <section className="editor">
                    <aside>
                        <input
                            aria-label="Buscar elemento"
                            placeholder="Buscar elemento"
                            value={search}
                            onChange={(e) => setSearch(e.target.value)}
                        />
                        <div className="list">
                            {draft?.document.features
                                .filter((f) =>
                                    f.name.toLocaleLowerCase().includes(search.toLocaleLowerCase()),
                                )
                                .map((f) => (
                                    <button
                                        key={f.id}
                                        className={'row ' + (selection === f.id ? 'selected' : '')}
                                        onClick={() => setSelection(f.id)}
                                    >
                                        <span>{f.name}</span>
                                        <small>{f.included ? 'Se incluirá' : 'Borrador'}</small>
                                    </button>
                                ))}
                        </div>
                        <button
                            className="secondary"
                            disabled={!draft || busy}
                            onClick={() => {
                                if (!draft) return;
                                const groups = draft.document.groups.length
                                    ? draft.document.groups
                                    : [{ id: crypto.randomUUID(), name: 'Recorridos' }];
                                const f: Feature = {
                                    id: crypto.randomUUID(),
                                    name: 'Nuevo lugar',
                                    groupID: groups[0].id,
                                    kind: 'reference',
                                    color: '#2476E8',
                                    geometry: { type: 'Point', coordinates: [-117, 32.5] },
                                    included: false,
                                    publicDescription: '',
                                    publicFields: [],
                                };
                                updateDocument({
                                    groups,
                                    features: [...draft.document.features, f],
                                });
                                setSelection(f.id);
                            }}
                        >
                            Añadir elemento
                        </button>
                    </aside>
                    <article>
                        {feature && draft ? (
                            <>
                                <div className="feature-title">
                                    <h2>{feature.name}</h2>
                                    <label className="check">
                                        <input
                                            type="checkbox"
                                            checked={feature.included}
                                            onChange={(e) => patch({ included: e.target.checked })}
                                        />
                                        Incluir en publicación
                                    </label>
                                </div>
                                <GeometryPreview feature={feature} />
                                <div className="fields">
                                    <label>
                                        Nombre
                                        <input
                                            value={feature.name}
                                            onChange={(e) => patch({ name: e.target.value })}
                                        />
                                    </label>
                                    <label>
                                        Grupo
                                        <select
                                            value={feature.groupID}
                                            onChange={(e) => patch({ groupID: e.target.value })}
                                        >
                                            {draft.document.groups.map((g) => (
                                                <option key={g.id} value={g.id}>
                                                    {g.name}
                                                </option>
                                            ))}
                                        </select>
                                    </label>
                                    <label>
                                        Tipo
                                        <select
                                            value={feature.kind}
                                            onChange={(e) =>
                                                patch({ kind: e.target.value as Feature['kind'] })
                                            }
                                        >
                                            <option value="route">Recorrido</option>
                                            <option value="stop">Parada</option>
                                            <option value="reference">Lugar o referencia</option>
                                            <option value="area">Área</option>
                                        </select>
                                    </label>
                                    <label>
                                        Color
                                        <input
                                            type="color"
                                            value={feature.color}
                                            onChange={(e) => patch({ color: e.target.value })}
                                        />
                                    </label>
                                </div>
                                <label>
                                    Descripción pública
                                    <textarea
                                        value={feature.publicDescription}
                                        onChange={(e) =>
                                            patch({ publicDescription: e.target.value })
                                        }
                                    />
                                </label>
                                <h3>Información pública</h3>
                                {feature.publicFields.map((v, i) => (
                                    <div className="field-row" key={i}>
                                        <select
                                            aria-label="Categoría"
                                            value={v.category}
                                            onChange={(e) =>
                                                patch({
                                                    publicFields: feature.publicFields.map(
                                                        (v, j) =>
                                                            i === j
                                                                ? { ...v, category: e.target.value }
                                                                : v,
                                                    ),
                                                })
                                            }
                                        >
                                            {Object.entries({
                                                schedule: 'Horario',
                                                fare: 'Tarifa',
                                                places: 'Lugares',
                                                direction: 'Sentido',
                                                note: 'Nota',
                                                contact: 'Contacto',
                                                media: 'Enlace',
                                            }).map(([c, label]) => (
                                                <option key={c} value={c}>
                                                    {label}
                                                </option>
                                            ))}
                                        </select>
                                        <input
                                            aria-label="Etiqueta"
                                            value={v.label}
                                            onChange={(e) =>
                                                patch({
                                                    publicFields: feature.publicFields.map(
                                                        (v, j) =>
                                                            i === j
                                                                ? { ...v, label: e.target.value }
                                                                : v,
                                                    ),
                                                })
                                            }
                                        />
                                        <input
                                            aria-label="Valor"
                                            value={v.value}
                                            onChange={(e) =>
                                                patch({
                                                    publicFields: feature.publicFields.map(
                                                        (v, j) =>
                                                            i === j
                                                                ? { ...v, value: e.target.value }
                                                                : v,
                                                    ),
                                                })
                                            }
                                        />
                                        <button
                                            className="secondary"
                                            aria-label="Quitar campo"
                                            onClick={() =>
                                                patch({
                                                    publicFields: feature.publicFields.filter(
                                                        (_, j) => i !== j,
                                                    ),
                                                })
                                            }
                                        >
                                            ×
                                        </button>
                                    </div>
                                ))}
                                <button
                                    className="secondary"
                                    onClick={() =>
                                        patch({
                                            publicFields: [
                                                ...feature.publicFields,
                                                { category: 'note', label: '', value: '' },
                                            ],
                                        })
                                    }
                                >
                                    Añadir dato
                                </button>
                                <label>
                                    Notas privadas
                                    <textarea
                                        value={feature.privateNotes ?? ''}
                                        onChange={(e) => patch({ privateNotes: e.target.value })}
                                    />
                                </label>
                                {source && (
                                    <details>
                                        <summary>Información de trabajo</summary>
                                        <p className="original">{source.description}</p>
                                        {source.description && (
                                            <button
                                                className="secondary"
                                                onClick={() =>
                                                    patch({
                                                        publicDescription: source.description!,
                                                    })
                                                }
                                            >
                                                Usar descripción en publicación
                                            </button>
                                        )}
                                        {source.fields?.map((v, i) => (
                                            <p key={i}>
                                                <strong>{v.label}: </strong>
                                                {v.value}{' '}
                                                <button
                                                    className="link"
                                                    onClick={() =>
                                                        patch({
                                                            publicFields: [
                                                                ...feature.publicFields,
                                                                {
                                                                    category: v.category,
                                                                    label: v.label,
                                                                    value: v.value,
                                                                },
                                                            ],
                                                        })
                                                    }
                                                >
                                                    Añadir a publicación
                                                </button>
                                            </p>
                                        ))}
                                    </details>
                                )}
                                <button
                                    className="danger"
                                    onClick={() => {
                                        if (confirm('¿Quitar este elemento del borrador?')) {
                                            updateDocument({
                                                ...draft.document,
                                                features: draft.document.features.filter(
                                                    (f) => f.id !== feature.id,
                                                ),
                                            });
                                            setSelection('');
                                        }
                                    }}
                                >
                                    Quitar elemento
                                </button>
                            </>
                        ) : (
                            <div className="empty">
                                <h2>Información del catálogo</h2>
                                <p>Importa un archivo o selecciona un elemento para editarlo.</p>
                            </div>
                        )}
                    </article>
                </section>
                {draft && (
                    <section className="card">
                        <h2>Grupos</h2>
                        {draft.document.groups.map((g) => (
                            <label key={g.id}>
                                Nombre del grupo
                                <input
                                    value={g.name}
                                    onChange={(e) =>
                                        updateDocument({
                                            ...draft.document,
                                            groups: draft.document.groups.map((v) =>
                                                v.id === g.id ? { ...v, name: e.target.value } : v,
                                            ),
                                        })
                                    }
                                />
                            </label>
                        ))}
                        <button
                            className="secondary"
                            onClick={() =>
                                updateDocument({
                                    ...draft.document,
                                    groups: [
                                        ...draft.document.groups,
                                        { id: crypto.randomUUID(), name: 'Nuevo grupo' },
                                    ],
                                })
                            }
                        >
                            Añadir grupo
                        </button>
                    </section>
                )}
                {preview && (
                    <section className="card publication">
                        <h2>Contenido de la publicación</h2>
                        <p>
                            Se entregará este catálogo a la aplicación. No incluye las notas ni los
                            archivos de trabajo.
                        </p>
                        <pre>{JSON.stringify(JSON.parse(preview.payload), null, 2)}</pre>
                        <div className="actions">
                            <button
                                disabled={busy || dirty}
                                onClick={() =>
                                    void run(async () => {
                                        await service.publish(preview);
                                        setPreview(null);
                                        setVersions(await service.versions());
                                        setAudit(await service.audit());
                                        setMessage('Publicación disponible.');
                                    })
                                }
                            >
                                Publicar esta versión
                            </button>
                            <button className="secondary" onClick={() => setPreview(null)}>
                                Cerrar vista previa
                            </button>
                        </div>
                    </section>
                )}
                {role === 'admin' && (
                    <>
                        <section className="card">
                            <h2>Publicaciones</h2>
                            {versions.map((v) => (
                                <div className="history" key={v.version}>
                                    <span>
                                        {new Date(v.created_at).toLocaleString()}
                                        <small>
                                            {v.version} · {v.created_by}
                                        </small>
                                    </span>
                                    <button
                                        className="secondary"
                                        disabled={busy}
                                        onClick={() => {
                                            if (confirm('¿Usar esta publicación en la app?'))
                                                void run(async () => {
                                                    await service.restore(v.version);
                                                    setAudit(await service.audit());
                                                    setMessage('Publicación restaurada.');
                                                });
                                        }}
                                    >
                                        Restaurar publicación
                                    </button>
                                </div>
                            ))}
                        </section>
                        <section className="card">
                            <h2>Equipo</h2>{members.map(member=><div className="history" key={member.user_id}><span>{member.user_id}<small>{member.role==='admin'?'Administrador':'Editor'}</small></span>{member.role==='editor'&&<button className="secondary" disabled={busy} onClick={()=>{if(confirm('¿Quitar el acceso de este editor?'))void run(async()=>{await service.revoke(member.user_id);setMembers(await service.members());});}}>Quitar acceso</button>}</div>)}
                            <form
                                className="actions"
                                onSubmit={(e) => {
                                    e.preventDefault();
                                    void run(async () => {
                                        await service.invite(email);
                                        setEmail('');
                                        setMessage('Invitación preparada.');
                                    });
                                }}
                            >
                                <label>
                                    Correo del editor
                                    <input
                                        type="email"
                                        value={email}
                                        onChange={(e) => setEmail(e.target.value)}
                                        required
                                    />
                                </label>
                                <button disabled={busy}>Invitar editor</button>
                            </form>
                        </section>
                    </>
                )}
                <section className="card">
                    <h2>Actividad</h2>
                    {audit.map((a) => (
                        <div className="history" key={a.id}>
                            <span>
                                {a.action} · {a.actor}
                                <small>
                                    {new Date(a.created_at).toLocaleString()} ·{' '}
                                    {a.version ?? 'Revisión ' + a.revision}
                                </small>
                            </span>
                        </div>
                    ))}
                </section>
            </main>
        </>
    );
}
