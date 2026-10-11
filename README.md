# Rutas Tijuana



Prototipo de una app de rutas en Tijuana, desarrollado en SwiftUI.

La interfaz muestra el estado de una consulta y lo actualiza al pulsar **Consultar horarios**. Esta versión no incluye datos de rutas, horarios ni conexión con servicios externos.

## Requisitos

- macOS con Xcode 16.4 o posterior.
- iOS 17+, macOS 14+ o visionOS 1+.
- Sin dependencias externas.

## Ejecutar

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
  Assets.xcassets/
RutasTijuana.xcodeproj/
docs/
  DESARROLLO.md

```

La compilación para iOS, macOS y visionOS se verifica en GitHub Actions. Los comandos y el flujo de validación están en [Desarrollo](docs/DESARROLLO.md).

Los cambios se realizan mediante issues, ramas y pull requests. El proceso está en [Colaboración](CONTRIBUTING.md).
