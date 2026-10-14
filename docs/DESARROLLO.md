# Desarrollo

## Organización

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
