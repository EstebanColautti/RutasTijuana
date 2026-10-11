# Rutas Tijuana

Proyecto de ICB103 · Estadística Aplicada · CETYS Universidad · Equipo 6 · 2026S2.

Prototipo para ayudar a habitantes de Tijuana que dependen del transporte público a consultar información clara sobre rutas, paradas, horarios y frecuencias.

La interfaz muestra el estado de una consulta y lo actualiza al pulsar **Consultar horarios**. Esta versión no incluye datos de rutas, horarios ni conexión con servicios externos.

## Alcance

La primera función prevista es la consulta de horarios y frecuencias por ruta, con fuente y fecha de actualización. También se contempla una ficha con origen, destino y paradas principales. El mapa de recorridos y la consulta de paradas cercanas requieren datos oficiales y validación.

El contexto, los requisitos y las métricas están en [Proyecto](docs/PROYECTO.md).

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
  PROYECTO.md
```

La compilación para iOS, macOS y visionOS se verifica en GitHub Actions. Los comandos y el flujo de validación están en [Desarrollo](docs/DESARROLLO.md).

Los cambios se realizan mediante issues, ramas y pull requests. El proceso está en [Colaboración](CONTRIBUTING.md).
