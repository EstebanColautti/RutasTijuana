import { useEffect, useState } from 'react';
export function Photo({ id, load }: { id: string; load?: (id: string) => Promise<string | null> }) {
    const [image, setImage] = useState<string | null>(null);
    useEffect(() => {
        let active = true;
        setImage(null);
        if (load) void load(id).then(value => {
            if (active && value && value.length <= 2900000 && /^[A-Za-z0-9+/=\s]+$/.test(value)) setImage(value.replace(/\s/g, ''));
        }).catch(() => {});
        return () => { active = false; };
    }, [id, load]);
    return image ? <img src={'data:image/jpeg;base64,' + image} alt="Fotografía del transporte" style={{ maxWidth: '100%', maxHeight: 240 }} /> : <p>Fotografía no disponible.</p>;
}
