export async function prepareImage(file: File): Promise<{ image: string; width: number; height: number }> {
    if (file.size > 2 * 1024 * 1024 || !['image/jpeg', 'image/png', 'image/webp'].includes(file.type))
        throw new Error('Elige una imagen JPG, PNG o WebP de hasta 2 MB.');
    const bitmap = await createImageBitmap(file);
    try {
        if (bitmap.width > 4096 || bitmap.height > 4096 || bitmap.width < 1 || bitmap.height < 1)
            throw new Error('La imagen supera 4096 píxeles.');
        const canvas = document.createElement('canvas');
        canvas.width = bitmap.width; canvas.height = bitmap.height;
        const context = canvas.getContext('2d');
        if (!context) throw new Error('No se pudo preparar la imagen.');
        context.fillStyle = '#ffffff'; context.fillRect(0, 0, canvas.width, canvas.height);
        context.drawImage(bitmap, 0, 0);
        const blob = await new Promise<Blob>((resolve, reject) => canvas.toBlob(value => value ? resolve(value) : reject(new Error('No se pudo preparar la imagen.')), 'image/jpeg', 0.9));
        if (blob.size > 2 * 1024 * 1024) throw new Error('La imagen preparada supera 2 MB.');
        const image = btoa(Array.from(new Uint8Array(await blob.arrayBuffer()), b => String.fromCharCode(b)).join(''));
        return { image, width: canvas.width, height: canvas.height };
    } finally { bitmap.close(); }
}
