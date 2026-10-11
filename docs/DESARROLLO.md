# Desarrollo

## Organización

`RutasTijuanaApp` define el punto de entrada y presenta `ContentView`. La vista mantiene el estado de consulta mediante `@State`. Los recursos visuales se encuentran en `Assets.xcassets`.

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

Para validar la interfaz, abrir la app y comprobar que el estado inicial sea **Pendiente**. Pulsar **Consultar horarios** y verificar que cambie a **Consulta registrada**. La consulta no genera solicitudes de red ni persiste datos.
