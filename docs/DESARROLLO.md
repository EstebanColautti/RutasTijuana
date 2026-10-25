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

En la app, abrir **Explorar recorridos > Abrir catálogo** y elegir el JSON. El archivo no se guarda, no se sube ni se incorpora al bundle. Debug permite catálogos de evaluación; Release exige `publishable=true` y `licenseStatus=verified`. Esos valores deben corresponder a una revisión real de los datos.

La app no calcula recorridos operativos, paradas ni transbordos desde una línea. Los catálogos sin verificación muestran ese estado y no ofrecen horarios o frecuencias supuestos. Los polígonos mantienen sus anillos interiores.

## Vista en Windows

Abrir `preview/index.html` y seleccionar el mismo catálogo local. La vista web reproduce la consulta, los filtros y la selección sobre una cuadrícula local; la app nativa usa MapKit. No requiere un servidor ni carga recursos externos. La validación final de la interfaz nativa se realiza con Xcode y las pruebas de iPhone.

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

Para macOS, usar `-destination 'platform=macOS'`. Para visionOS, usar `-destination 'generic/platform=visionOS Simulator'` con su SDK instalado.

## Validación

GitHub Actions compila las tres plataformas en cada push a `main` y en los pull requests. La ejecución manual se inicia desde la pestaña **Actions**.

Las pruebas de lógica se ejecutan en el trabajo macOS de GitHub Actions:

```sh
swiftc RutasTijuana/TransitRoute.swift tests/main.swift -o /tmp/route-tests
/tmp/route-tests
```

Para revisar la interfaz en Xcode:

1. Comenzar una consulta sin conceder ubicación y elegir una parada como origen.
2. Elegir otra parada como destino y comprobar dónde subir y bajar.
3. Elegir la misma parada en ambos extremos y comprobar el aviso.
4. Volver desde el resultado y comprobar que se conserve la selección.
5. Pulsar **Nueva consulta** y comprobar que se borren ambos puntos.
6. Probar ubicación permitida, denegada y fuera del circuito; la selección manual debe seguir disponible.
7. Revisar modo oscuro, texto grande y lectura con VoiceOver.
