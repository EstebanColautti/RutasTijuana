# Rutas Tijuana

Prototipo de una app de rutas en Tijuana, desarrollado en SwiftUI.

La app permite elegir origen y destino, seleccionar paradas cercanas y consultar un trayecto en el mapa. Incluye un circuito ficticio con seis paradas para probar la navegación. No contiene rutas, paradas ni horarios de transporte reales.

La selección usa un panel inferior, búsqueda de paradas y lugares, y permite continuar desde la lista sin conexión. Los escenarios de evaluación se abren desde un JSON local en Debug.

**Explorar recorridos** permite abrir un catálogo JSON local, buscar por nombre o grupo y consultar trazados próximos a un punto. Las áreas se muestran como referencias. La cercanía no confirma un lugar de ascenso ni un trayecto peatonal.

Los catálogos de evaluación se abren únicamente en compilaciones de desarrollo. Se mantienen en memoria y fuera del paquete de la app. La carga, el formato y la vista para Windows están descritos en [Desarrollo](docs/DESARROLLO.md).

## Requisitos

- macOS con Xcode 16.4 o posterior.
- iPhone con iOS 17 o posterior.
- Sin dependencias externas.

## Ejecutar

Para editar en VS Code, abrir `RutasTijuana.code-workspace`. Las tareas y los requisitos del entorno están en [Desarrollo](docs/DESARROLLO.md).

```sh
git clone https://github.com/EstebanColautti/RutasTijuana.git
cd RutasTijuana
open RutasTijuana.xcodeproj
```

Seleccionar el esquema **RutasTijuana**, elegir un simulador de iPhone y ejecutar con `⌘R`. Para un dispositivo físico, configurar el equipo de firma en **Signing & Capabilities**.

## Estructura

```text
RutasTijuana/
  RutasTijuanaApp.swift
  ContentView.swift
  TransitRoute.swift
  LocationService.swift
  Assets.xcassets/
RutasTijuana.xcodeproj/
docs/
  DESARROLLO.md
tests/
  main.swift
```

La compilación para iPhone se verifica en GitHub Actions. Los comandos y el flujo de validación están en [Desarrollo](docs/DESARROLLO.md).
