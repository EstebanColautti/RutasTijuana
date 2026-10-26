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

En la app, abrir **Explorar recorridos > Abrir catálogo** y elegir el JSON. El archivo no se guarda, no se sube ni se incorpora al bundle. Debug permite catálogos de evaluación; Release exige `publishable=true` y `licenseStatus=verified`.

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
