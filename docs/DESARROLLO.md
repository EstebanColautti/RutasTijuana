# Desarrollo

## VS Code

Abrir `RutasTijuana.code-workspace` o seleccionar **Archivo > Abrir carpeta** y elegir la raíz del proyecto. Las extensiones recomendadas son Swift y EditorConfig.

`Ctrl+Shift+B` comprueba el formato del diff. En **Terminal > Ejecutar tarea** están las pruebas de lógica, el estado de Git y la compilación iOS para Mac.

Las pruebas de lógica funcionan en Windows con Swift, las herramientas C++ de Visual Studio y el SDK de Windows instalados. La interfaz SwiftUI, MapKit, el simulador y la compilación de la app requieren macOS con Xcode; el compilador de Windows no incluye esos frameworks.

```sh
code RutasTijuana.code-workspace
```

## Organización

`RouteCatalog` valida el esquema local, conserva coordenadas y anillos, filtra por nombre o grupo y calcula distancia al segmento más próximo. `CatalogView` muestra el catálogo y permite importar un JSON desde el selector de archivos. La consulta de trayectos de demostración sigue separada.

## Catálogo local

El archivo tiene `schemaVersion`, `version`, `publishable`, `licenseStatus`, `groups` y `features`. Cada elemento conserva `id`, `name`, `groupID`, `kind`, `color`, `verified` y una geometría GeoJSON. `kind` distingue `route`, `area` y `reference`. Las coordenadas usan longitud, latitud y altitud opcional. Los identificadores y las referencias de grupo deben ser únicos y válidos.

```sh
python scripts/prepare_catalog.py --data <carpeta-de-datos> --out local-data/TransitCatalog.json
```

El preparador usa `data/processed/all_features.geojson`, `data/processed/dataset_metadata.json` y `data/intermediate/layers.json`. Conserva los vértices y elimina los campos que la interfaz no necesita. La carpeta `local-data` está excluida de Git y fuera de los recursos de Xcode.

En la app, abrir **Explorar recorridos > Abrir catálogo** y elegir el JSON. La importación de desarrollo no se guarda ni se incorpora al paquete. La distribución utiliza el catálogo publicado desde la API.

El detalle de cada elemento muestra la descripción, los horarios y tarifas presentes, los destinos mencionados, los campos adicionales y las medidas geométricas. Los polígonos mantienen sus anillos interiores.

## Vista en Windows

En VS Code, ejecutar la tarea **Vista local** y abrir `http://127.0.0.1:8766`. Seleccionar el mismo catálogo local con **Abrir catálogo**. La vista web reproduce la consulta, los filtros y la selección sobre una cuadrícula local; la app nativa usa MapKit.

El servidor solo entrega los archivos de `preview`. El catálogo se procesa en el navegador sin enviarlo al servidor ni cargar recursos externos. La tarea necesita Python 3 y se detiene desde el terminal de VS Code. La validación final de la interfaz nativa se realiza con Xcode y las pruebas de iPhone.

## Componentes

`ContentView` contiene el flujo de inicio, origen, destino y resultado. `TransitRoute` calcula paradas cercanas y el recorrido de un circuito en sentido único. `LocationService` obtiene una ubicación puntual en iOS, solo después de pedirla; permite continuar manualmente si no está disponible.

Las seis paradas y sus coordenadas son ficticias. Las distancias se calculan en línea recta, no como caminos peatonales. El mapa base necesita conexión. No se guardan ubicaciones ni consultas.

El identificador de la aplicación es `com.estebancolautti.rutastijuana`. La firma utiliza la configuración local de Xcode; el repositorio no contiene certificados ni un equipo de desarrollo asignado.

## Compilación

Desde la raíz del repositorio, en macOS con Xcode seleccionado:

```sh
xcodebuild -project RutasTijuana.xcodeproj -scheme RutasTijuana \
  -configuration Release -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
```

El destino de la app es iPhone con iOS 17 o posterior.

## Validación

GitHub Actions compila para iPhone en cada push a `main` y en los pull requests. La ejecución manual se inicia desde la pestaña **Actions**.

Las pruebas de lógica se ejecutan en el runner de macOS de GitHub Actions:

```sh
bash scripts/test-logic.sh
```

Para revisar la interfaz en Xcode:

1. Comenzar una consulta sin conceder ubicación y elegir una parada como origen.
2. Elegir otra parada como destino y comprobar dónde subir y bajar.
3. Elegir la misma parada en ambos extremos y comprobar el aviso.
4. Volver desde el resultado y comprobar que se conserve la selección.
5. Pulsar **Nueva consulta** y comprobar que se borren ambos puntos.
6. Probar ubicación permitida, denegada y fuera del circuito; la selección manual debe seguir disponible.
7. Revisar modo oscuro, texto grande y lectura con VoiceOver.

## Escenarios de evaluación

**Abrir datos de evaluación** carga un JSON privado en memoria, solo en Debug. El esquema contiene `schemaVersion: 1`, `name`, `coverageRadius`, `stops` y `places`. Cada parada incluye `id`, `name` y `point` con `latitude` y `longitude`. Cada lugar incluye `id`, `name`, `subtitle`, `category`, `stopID` y `keywords`. Las referencias deben apuntar a paradas existentes.

Las asociaciones sirven para ensayar la interfaz. Release utiliza el catálogo de distribución. No se guardan consultas ni archivos importados.

El panel inferior conserva el mapa visible y puede ampliarse. La búsqueda ignora acentos y mayúsculas. Cambiar origen conserva la consulta hasta elegir otro punto; una nueva consulta borra las selecciones. Sin conexión se mantiene la lista; la disponibilidad del mapa depende de MapKit.

La información ampliada es opcional: `information.description` contiene el texto completo y `information.fields` conserva filas con `category`, `label`, `value`, `evidence` e `inferred`. Los catálogos anteriores siguen siendo compatibles. La búsqueda incluye este contenido. Las imágenes adjuntas se conservan como enlaces de texto y no se cargan automáticamente.

## Servicios y panel

Las tareas **Servicios locales** y **Panel privado** preparan la base, la autenticación, la API y la administración. Las imágenes y la herramienta de Supabase se descargan desde sus distribuciones oficiales. Los servicios se limitan a `127.0.0.1`; no se crea ningún proyecto remoto.

En Windows se necesita WSL con Podman y Python 3. Las tareas preparan Node.js y pnpm dentro de `local-data/tools` cuando es necesario, sin cambiar la configuración global. En macOS se utiliza Docker o un socket compatible. `scripts/local-stack.sh start` inicia la base; después, ejecutar `node scripts/local-config.mjs` y `pnpm dev`. La tarea de Windows realiza los dos primeros pasos.

- Panel: `http://127.0.0.1:5173`.
- Catálogo: `http://127.0.0.1:54321/functions/v1/catalog`.
- Correo local de invitaciones: `http://127.0.0.1:54324`.

La cuenta inicial es local y su contraseña está en `local-data/access.json`. El usuario configura TOTP al ingresar. Los registros públicos están separados del borrador: importar un catálogo conserva su información de trabajo y deja los elementos sin seleccionar para publicación. El administrador revisa la vista previa antes de publicar.

Las invitaciones se reciben en el correo local. El editor configura su contraseña y autenticador desde el enlace. El administrador puede quitar su acceso desde **Equipo**. No existe registro público de usuarios del panel.

**Exportar respaldo** descarga el borrador completo. Para recuperarlo, utilizar **Importar catálogo**, guardar y preparar una publicación cuando corresponda. **Restaurar publicación** cambia la versión disponible para la app y conserva el borrador de edición.

La tarea **API local (desarrollo)** activa la recarga de funciones durante cambios de código. Para detener la base sin perder datos, usar **Detener servicios locales** y cerrar el terminal del panel.

## Catálogo publicado

La API devuelve un manifiesto con `version`, `schemaVersion`, `bytes`, `sha256` y `downloadURL`. La dirección de descarga puede ser relativa al manifiesto. El esquema 2 conserva grupos, identificadores, geometrías, descripciones y campos públicos. El contenido publicado se mantiene inmutable.

`CatalogRepository` coordina la carga y actualización; `CatalogSynchronizer` comprueba el manifiesto y el contenido, y `SQLiteCatalogCache` reemplaza la copia mediante una transacción. Los datos privados importados no se escriben en esa base. Las descargas tienen límites de tamaño y tiempo y no siguen redirecciones.

Las migraciones y funciones de Supabase se conservan en el repositorio. El panel utiliza únicamente la clave pública del proyecto; las operaciones administrativas de invitación se ejecutan en el servidor. Los permisos de edición y publicación se comprueban en PostgreSQL.

## iPhone y conexión local

Debug utiliza `http://127.0.0.1:54321/functions/v1/catalog`. Para un simulador de iPhone, los servicios deben ejecutarse en la misma Mac. La dirección local de Windows no es accesible desde un iPhone físico.

La dirección se configura mediante `CATALOG_MANIFEST_URL`. Se puede sobrescribir en `Config/Debug.local.xcconfig` o `Config/Release.local.xcconfig`, excluidos de Git. Release admite únicamente HTTPS. Los entornos se cambian mediante configuración, sin modificar las pantallas.

El proyecto no incluye datos reales ni credenciales. Para una futura instalación remota, aplicar las migraciones, configurar la autenticación por invitación y doble factor, definir el origen del panel en `ADMIN_ORIGIN` y establecer la dirección HTTPS del manifiesto. El panel genera archivos estáticos mediante `pnpm build`; no se despliega automáticamente.

## Pruebas de administración

```sh
pnpm test
pnpm build
node --test tests/catalog-preview.test.cjs
```

Las pruebas de base ejecutan las migraciones en PostgreSQL mediante PGlite. Comprueban permisos, doble factor, publicación, conflictos, restauración y exclusión de campos privados. Las pruebas del panel comprueban edición y confirmación de publicación. Las pruebas Swift incluyen actualización y almacenamiento; GitHub Actions comprueba también SQLite y la interfaz de iPhone.
