# Rutas Tijuana



Prototipo de una app de rutas en Tijuana, desarrollado en SwiftUI.

La app permite elegir origen y destino, seleccionar paradas cercanas y consultar un trayecto en el mapa. Incluye un circuito ficticio con seis paradas para probar la navegación. No contiene rutas, paradas ni horarios de transporte reales.

## Requisitos

- macOS con Xcode 16.4 o posterior.
- iOS 17+, macOS 14+ o visionOS 1+.
- Sin dependencias externas.

## Ejecutar

Para editar en VS Code, abrir `RutasTijuana.code-workspace`. Las tareas y los requisitos del entorno están en [Desarrollo](docs/DESARROLLO.md).

```sh
git clone https://github.com/EstebanColautti/RutasTijuana.git
cd RutasTijuana
open RutasTijuana.xcodeproj
```

Seleccionar el esquema **RutasTijuana**, elegir un simulador o **My Mac** y ejecutar con `⌘R`. Para un dispositivo físico, configurar el equipo de firma en **Signing & Capabilities**.

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

La compilación para iOS, macOS y visionOS se verifica en GitHub Actions. Los comandos y el flujo de validación están en [Desarrollo](docs/DESARROLLO.md).
