# Colaboración

## Flujo

1. Registrar el problema o cambio en un issue, con alcance y criterio de aceptación.
2. Actualizar `main` y crear una rama para ese issue.
3. Implementar cambios pequeños y completar la documentación necesaria.
4. Comprobar el diff y ejecutar las pruebas correspondientes al cambio.
5. Abrir un pull request en borrador, enlazado al issue.
6. Revisar el diff, resolver observaciones y pasar el PR a listo para revisión.
7. Integrar cuando las verificaciones sean correctas y la rama esté actualizada.
8. Usar squash, eliminar la rama y actualizar la copia local de `main`.

## Ramas y commits

Ramas: `feat/numero-descripcion`, `fix/numero-descripcion`, `docs/numero-descripcion` o `chore/numero-descripcion`.

Los commits describen un cambio concreto, en español y con mensajes breves: «Agrega ficha de ruta», «Corrige estado de consulta» o «Actualiza requisitos».

No se suben cambios directamente a `main`. No se reescribe su historial ni se desactivan las protecciones para integrar un cambio.

## Revisión y validación

El PR debe explicar el problema, el resultado y la validación realizada. El título debe describir el cambio que quedará en el historial.

Revisar funcionamiento, alcance, datos personales, documentación y pruebas. Si participa otro integrante, solicitar su revisión. Las reglas actuales exigen PR y verificaciones; no exigen una aprobación externa.

GitHub exige que pasen las compilaciones de iOS, macOS y visionOS y que las conversaciones estén resueltas. Los cambios de interfaz también necesitan pruebas de interacción y capturas reales. Una compilación correcta no equivale a una prueba de uso.

## Versiones

Publicar una release cuando exista una entrega validada. Usar etiquetas `vMAJOR.MINOR.PATCH` y describir cambios, requisitos y limitaciones. Durante el prototipo, usar versiones `0.x.y`. Cada release debe apuntar a un commit integrado y verificado de `main`.

Las funciones y restricciones del producto están en [Proyecto](docs/PROYECTO.md); los comandos de compilación, en [Desarrollo](docs/DESARROLLO.md).
