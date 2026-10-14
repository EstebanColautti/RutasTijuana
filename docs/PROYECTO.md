# Proyecto

## Problema y población

El proyecto aborda la dificultad para consultar información clara y didáctica sobre rutas, paradas y horarios del transporte público en Tijuana. Su alcance es informativo: no modifica la operación del transporte ni resuelve problemas de infraestructura o seguridad vial.

El enfoque inicial eran los trayectos escolares. Desde S13, la población de interés se amplió a habitantes de Tijuana que usan o dependen del transporte público.

## Evidencia

Las entregas del equipo registran estos antecedentes:

- El PIMUS 2019 reporta que el transporte público representó 24.26% de los desplazamientos de la Encuesta Origen-Destino 2017. Es un dato histórico de viajes, no un porcentaje de habitantes ni una medición de 2026.
- La evaluación FPAE SITT 2025 contiene una tabla de 249 registros de sugerencias de la Ruta Troncal. El equipo agrupó 74 registros relacionados con horarios y frecuencia: 43 de «Ampliar y cumplir horarios», 29 de «Salidas cada 30 min» y 2 de «Salidas cada 15 min».
- Los registros no están confirmados como usuarios únicos. Las solicitudes de mejorar el servicio no demuestran por sí solas una necesidad de información. La categoría «Todo bien» tampoco equivale a una tasa general de satisfacción.

En S16 se sustituyó el 33.3% utilizado en S14–S15 por el 24.26% reportado en el PIMUS, al no poder verificar el origen de los 36/108 casos. Los datos del PIMUS y las sugerencias del SITT describen fenómenos distintos y no se usan para calcular una brecha entre ambos.

Estos antecedentes justifican explorar el problema. No constituyen un catálogo actualizado de rutas, paradas o horarios.

## Funciones previstas

| Función | Requisito | Estado |
|---|---|---|
| Consulta de horarios y frecuencias | Mostrar la información de cada ruta, su fuente y fecha de actualización | Función elegida para el prototipo S18; datos oficiales pendientes |
| Ficha de ruta | Mostrar origen, destino y paradas principales, con fuente y fecha | Prevista; recorridos y paradas pendientes |
| Paradas cercanas | Consultar paradas desde una colonia o punto elegido | Por validar; requiere un listado de paradas |
| Mapa de recorridos | Mostrar el recorrido de las rutas incluidas | Por precisar y validar |

## Criterios de diseño

- Consultar información básica sin crear una cuenta ni proporcionar datos personales.
- Mostrar fuente y fecha de actualización de la información.
- Ofrecer selección manual de colonia o punto; la ubicación del dispositivo sería opcional y con autorización previa.
- No guardar historial de ubicación.
- Distinguir rutas y estados mediante texto e identificadores, además del color.
- No presentar datos históricos como actuales ni prometer tiempos exactos, menor duración de viajes o impacto social demostrado.

Pagos, transacciones y seguimiento permanente de ubicación quedan fuera del alcance documentado.

## Estado y evaluación

La base actual sigue el wireframe de inicio, origen, destino y trayecto, con un circuito ficticio de seis paradas. Incluye selección manual, ubicación opcional en iOS y validación de destinos. Los horarios siguen sin datos disponibles. La simulación permite probar navegación y lógica; no demuestra que exista un servicio de transporte con ese recorrido.

La ficha S18 conserva el estado de la entrega anterior:

S18 corresponde a una interacción mínima: la app muestra nombre y propósito, y el botón **Consultar horarios** cambia el estado de **Pendiente** a **Consulta registrada**. No muestra horarios reales.

La ficha registra tres comprobaciones técnicas: apertura de la app, nombre y propósito visibles, y cambio de estado del botón. Reporta 3 de 3 pruebas superadas; ese resultado describe únicamente esas pruebas, no la utilidad de la app ni su impacto social.

La métrica de uso propuesta es `(intentos completados / intentos iniciados) × 100`, mediante pruebas del equipo sin nombres ni identificadores. Los intentos, la línea base y la meta siguen pendientes de registro y validación.

Antes de incorporar información real, falta obtener y verificar rutas, paradas, horarios y frecuencias de fuentes oficiales. Las pruebas posteriores deberán comprobar si esa información permite identificar una ruta y planear un trayecto.

## Referencias

- [Entregas S11–S18 del equipo](https://drive.google.com/drive/u/1/folders/1fJB67UI5qw6OcqOs0H7lW-rj_IevIOwr).
- [S16 · Visualización y narrativa](https://drive.google.com/file/d/1KyiQCytvMuN6qCfjGeEAjBy-PJa_2Z-K/view).
- [S17 · Requisitos de producto](https://drive.google.com/file/d/1HOxlBS-Jd_ZTveTcQovi-5dJK6Z0fHK9/view).
- [S18 · Prototipo y métricas](https://drive.google.com/file/d/1j_MdfMVtaKSRq_HNhuoEJ0ynV5XhnoE6/view).

Fuentes citadas en las entregas:

- [PIMUS Tijuana 2019–2040 · IMPLAN](https://implan.tijuana.gob.mx/implan/planes-y-programas/pdf/PIMUSTJ_VT_30-08-2019.pdf).
- [Evaluación FPAE SITT 2025](https://www.tijuana.gob.mx/dependencias/tesoreria/PDF/evaluaciones/2025/2.paramunicipal/102_SITT_FPAE_2025.pdf).
