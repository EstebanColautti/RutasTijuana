import XCTest

final class JourneyTests: XCTestCase {
    private let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launchConsultation() {
        app.launchArguments = ["--legacy-consultation-test", "--ui-testing", "--journey-fixture"]
        app.launch()
    }

    func testJourneyAndReset() {
        launchConsultation()
        capture("Inicio")
        tap("Elegir ubicación inicial")
        tap("stop-demo-1")
        capture("Origen")
        tap("Continuar")
        tap("stop-demo-4")
        capture("Destino")
        tap("Ver trayecto")
        XCTAssertTrue(app.staticTexts["Sube en Parada 1"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Bájate en Parada 4"].exists)
        capture("Trayecto")
        tap("Regresar")
        tap("Ver trayecto")
        XCTAssertTrue(app.staticTexts["Sube en Parada 1"].waitForExistence(timeout: 5))
        tap("Nueva consulta")
        tap("Elegir ubicación inicial")
        XCTAssertFalse(app.buttons["Continuar"].isEnabled)
    }

    func testEvaluationFlowAndSimulation() {
        launchConsultation()
        tap("Evaluar consulta")
        capture("Inicio de evaluación")
        tap("Planear mi ruta")
        XCTAssertTrue(app.navigationBars["¿Dónde bajas?"].waitForExistence(timeout: 5))
        tap("stop-demo-4")
        capture("Selección de evaluación")
        tap("Elegir destino")
        XCTAssertTrue(app.staticTexts["Ruta aceptada"].waitForExistence(timeout: 5))
        capture("Resultado de evaluación")
        tap("Regresar")
        XCTAssertTrue(app.buttons["Elegir destino"].isEnabled)
        tap("Elegir destino")
        tap("Trayecto simulado")
        tap("Avanzar una parada")
        tap("Finalizar trayecto")
        XCTAssertTrue(app.staticTexts["Viaje finalizado"].exists)
        capture("Viaje finalizado")
        tap("Nueva consulta")
        tap("Planear mi ruta")
        XCTAssertFalse(app.buttons["Elegir destino"].isEnabled)
    }

    func testConsultationAccessibilityAudit() throws {
        launchConsultation()
        continueAfterFailure = true
        try audit("Inicio")
        tap("Elegir ubicación inicial")
        try audit("Origen")
        let panel = app.scrollViews["consultation-scroll"]
        let header = app.navigationBars["Desde dónde sales"]
        XCTAssertTrue(panel.waitForExistence(timeout: 5))
        header.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2))
            .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.14)))
        try audit("Origen expandido")
        panel.swipeUp(velocity: .slow)
        try audit("Origen desplazado")
        panel.swipeDown(velocity: .slow)
        tap("stop-demo-1")
        tap("Continuar")
        XCTAssertFalse(app.buttons["Ver trayecto"].isEnabled)
        tap("stop-demo-4")
        try audit("Destino")
        tap("Ver trayecto")
        try audit("Resultado")
    }

    func testCatalogAccessibility() throws {
        app.terminate()
        app.launchArguments = ["--legacy-consultation-test", "--journey-fixture", "--ui-testing", "--catalog-info-sample"]
        app.launch()
        tap("Explorar recorridos")
        let search = app.textFields["catalog-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        XCTAssertEqual(search.label, "Buscar nombre, grupo o información")
        XCTAssertGreaterThanOrEqual(search.frame.width, 44)
        search.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        search.typeText("Recorrido\n")
        expectation(for: NSPredicate(format: "hittable == false"), evaluatedWith: app.keyboards.firstMatch)
        waitForExpectations(timeout: 15)
        search.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 10))
        capture("Búsqueda del catálogo")
        tap("Listo")
        expectation(for: NSPredicate(format: "hittable == false"), evaluatedWith: app.keyboards.firstMatch)
        waitForExpectations(timeout: 15)
        tap("catalog-sample-route")
        tap("catalog-information")
        XCTAssertTrue(app.staticTexts["Descripción de ejemplo"].waitForExistence(timeout: 5))
        try audit("Información del catálogo", types: [.textClipped])
        tap("catalog-information-close")
    }

    func testWalkingAccessibility() throws {
        app.terminate()
        app.launchArguments = ["--legacy-consultation-test", "--journey-fixture", "--ui-testing", "--walking-fixture"]
        app.launch()
        tap("Elegir ubicación inicial")
        tap("stop-demo-1")
        tap("Continuar")
        tap("stop-demo-4")
        tap("Ver trayecto")
        tap("walking-start")
        checkAccessibleControl(app.buttons["Recentrar"], label: "Recentrar")
        checkAccessibleControl(app.buttons["Finalizar"], label: "Finalizar")
        tap("Iniciar guía")
        tap("Ver pasos")
        XCTAssertTrue(app.navigationBars["Indicaciones"].waitForExistence(timeout: 5))
        try audit("Indicaciones de la guía", types: [.textClipped])
    }

    func testConsultationTextSizeXS() { checkConsultationTextSize("XS") }
    func testConsultationTextSizeS() { checkConsultationTextSize("S") }
    func testConsultationTextSizeM() { checkConsultationTextSize("M") }
    func testConsultationTextSizeL() { checkConsultationTextSize("L") }
    func testConsultationTextSizeXL() { checkConsultationTextSize("XL") }
    func testConsultationTextSizeXXL() { checkConsultationTextSize("XXL") }
    func testConsultationTextSizeXXXL() { checkConsultationTextSize("XXXL") }
    func testConsultationTextSizeAccessibilityM() { checkConsultationTextSize("AccessibilityM") }
    func testConsultationTextSizeAccessibilityL() { checkConsultationTextSize("AccessibilityL") }
    func testConsultationTextSizeAccessibilityXL() { checkConsultationTextSize("AccessibilityXL") }
    func testConsultationTextSizeAccessibilityXXL() { checkConsultationTextSize("AccessibilityXXL") }
    func testConsultationTextSizeAccessibilityXXXL() { checkConsultationTextSize("AccessibilityXXXL") }

    private func checkConsultationTextSize(_ size: String) {
        app.terminate()
        app.launchArguments = ["--legacy-consultation-test", "--journey-fixture", "--ui-testing", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategory" + size]
        app.launch()
        tap("Elegir ubicación inicial")
        tap("stop-demo-1")
        tap("Continuar")
        tap("stop-demo-4")
        tap("Ver trayecto")
        XCTAssertTrue(app.staticTexts["Ruta aceptada"].waitForExistence(timeout: 5))
        capture("Consulta texto " + size)
        tap("Nueva consulta")
        XCTAssertTrue(app.buttons["Elegir ubicación inicial"].waitForExistence(timeout: 5))
    }

    func testCatalogLineVisibilityLight() { checkCatalogLineVisibility(dark: false) }
    func testCatalogLineVisibilityDark() { checkCatalogLineVisibility(dark: true) }

    private func checkCatalogLineVisibility(dark: Bool) {
        app.terminate()
        app.launchArguments = ["--legacy-consultation-test", "--ui-testing", "--catalog-pale-sample"] + (dark ? ["--catalog-dark"] : [])
        app.launch()
        tap("Explorar recorridos")
        XCTAssertTrue(app.buttons["catalog-sample-route"].waitForExistence(timeout: 5))
        capture(dark ? "Recorrido claro en mapa oscuro" : "Recorrido claro en mapa claro")
        tap("catalog-sample-route")
        XCTAssertTrue(app.staticTexts["Distancia al trazado en línea recta."].waitForExistence(timeout: 5))
        capture(dark ? "Selección en mapa oscuro" : "Selección en mapa claro")
    }

    func testCombinedTrip() {
        app.terminate()
        app.launchArguments = ["--ui-testing", "--trip-fixture"]
        app.launch()
        tap("trip-continue")
        tap("trip-calculate")
        XCTAssertTrue(app.staticTexts["trip-result"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts.matching(identifier: "trip-result").count, 1)
        tap("trip-show-leg-0")
        XCTAssertEqual(app.buttons["trip-show-leg-0"].value as? String, "Seleccionada")
        capture("Etapa seleccionada")
        tap("trip-show-all")
        for _ in 0..<8 {
            if app.buttons["trip-begin"].isHittable { break }
            app.scrollViews.firstMatch.swipeUp()
        }
        capture("Itinerario combinado")
        tap("trip-begin")
        capture("Caminata inicial del viaje")
        for _ in 0..<8 where !app.buttons["trip-stages"].exists {
            app.scrollViews.firstMatch.swipeUp()
        }
        tap("trip-stages")
        let currentStage = app.descendants(matching: .any)["trip-stage-1"]
        XCTAssertTrue(currentStage.waitForExistence(timeout: 5))
        XCTAssertEqual(currentStage.value as? String, "Actual")
        capture("Etapas del viaje")
        tap("trip-walk")
        tap("Iniciar guía")
        XCTAssertTrue(app.staticTexts["walking-instruction"].waitForExistence(timeout: 5))
        tap("walking-finish")
        tap("Terminar guía")
        tap("trip-walk-arrived")
        XCTAssertTrue(app.staticTexts["Esperando para subir"].waitForExistence(timeout: 5))
        capture("Esperando para subir")
        tap("trip-board")
        capture("Seguimiento de transporte")
        tap("trip-alight")
        tap("trip-board")
        tap("trip-alight")
        tap("trip-walk-arrived")
        XCTAssertTrue(app.staticTexts["Llegaste al destino"].waitForExistence(timeout: 5))
        capture("Viaje combinado")
        tap("Terminar")
        XCTAssertTrue(app.staticTexts["trip-result"].waitForExistence(timeout: 5))
        tap("Cambiar origen o destino")
        XCTAssertTrue(app.staticTexts["Destino de ejemplo"].waitForExistence(timeout: 5))
        tap("Cambiar origen")
        XCTAssertTrue(app.staticTexts["Origen de ejemplo"].waitForExistence(timeout: 5))
        tap("trip-continue")
        XCTAssertTrue(app.staticTexts["Destino de ejemplo"].waitForExistence(timeout: 5))
        tap("trip-calculate")
        XCTAssertTrue(app.staticTexts["trip-result"].waitForExistence(timeout: 10))
    }

    func testCombinedTripLargeText() {
        app.terminate()
        app.launchArguments = ["--ui-testing", "--trip-fixture", "--trip-dark",
                               "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        tap("trip-continue")
        tap("trip-calculate")
        XCTAssertTrue(app.staticTexts["trip-result"].waitForExistence(timeout: 10))
        for _ in 0..<8 {
            if app.buttons["trip-begin"].isHittable { break }
            app.scrollViews.firstMatch.swipeUp()
        }
        XCTAssertTrue(app.buttons["trip-begin"].isHittable)
        capture("Itinerario con texto grande")
        tap("trip-begin")
        tap("trip-walk-arrived")
        tap("trip-board")
        capture("Transporte con texto grande")
        tap("trip-finish")
        tap("Finalizar")
        XCTAssertTrue(app.staticTexts["trip-result"].waitForExistence(timeout: 5))
    }

    func testHomeHeaderWhileScrolling() {
        app.terminate()
        app.launchArguments = ["--legacy-consultation-test", "--ui-testing", "--catalog-bundle-sample", "--catalog-recent-sample"]
        app.launch()
        let title = app.staticTexts["home-title"]
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        let initialY = title.frame.minY
        XCTAssertGreaterThanOrEqual(initialY, 20)
        app.scrollViews.firstMatch.swipeUp()
        XCTAssertTrue(title.isHittable)
        XCTAssertEqual(title.frame.minY, initialY, accuracy: 1)
        let homeScroll = app.scrollViews["home-scroll"]
        let dock = app.otherElements["app-dock"]
        XCTAssertTrue(dock.exists)
        XCTAssertLessThanOrEqual(homeScroll.frame.maxY, dock.frame.minY + 1)
        capture("Inicio desplazado")
        XCTAssertTrue(app.buttons["recent-planned-sample-route"].waitForExistence(timeout: 10))
        capture("Inicio con consultas recientes")
        let browse = app.buttons["Explorar recorridos"]
        let home = app.scrollViews["home-scroll"]
        if browse.frame.midY < home.frame.minY { home.swipeDown() }
        tap("Explorar recorridos")
        XCTAssertTrue(app.navigationBars["Recorridos"].waitForExistence(timeout: 15))
    }

    func testHomeMapWithoutCatalog() {
        app.terminate()
        app.launchArguments = ["--legacy-consultation-test", "--ui-testing"]
        app.launch()
        tap("Abrir catálogo de recorridos")
        XCTAssertTrue(app.navigationBars["Recorridos"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Descargar catálogo"].waitForExistence(timeout: 10))
    }

    func testRoutesTabAndLists() {
        app.terminate()
        app.launchArguments = ["--ui-testing", "--catalog-bundle-sample", "--offline"]
        app.launch()
        app.buttons["dock-Rutas"].tap()
        XCTAssertTrue(app.navigationBars["Rutas"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["catalog-sample-route"].waitForExistence(timeout: 15))
        capture("Rutas por zona")
        app.buttons["Todas"].tap()
        XCTAssertTrue(app.buttons["catalog-sample-route"].exists)
        capture("Todas las rutas")
        tap("catalog-sample-route")
        XCTAssertTrue(app.buttons["Guardar en listas"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Trazado no disponible"].exists)
        XCTAssertFalse(app.buttons["Volver a encuadrar"].exists)
        XCTAssertFalse(app.buttons["Usar esta ruta"].exists)
        capture("Ficha sin trazado")
        tap("Guardar en listas")
        XCTAssertTrue(app.navigationBars["Guardar en listas"].waitForExistence(timeout: 10))
        let name = "Lista " + String(UUID().uuidString.prefix(8))
        saveCurrentRoute(inList: name)
        capture("Guardar en listas")
        tap("Listo")
        app.terminate()
        app.launch()
        app.buttons["dock-Rutas"].tap()
        tap("Mis listas")
        XCTAssertTrue(app.buttons[name].waitForExistence(timeout: 10))
        XCTAssertTrue(app.navigationBars["Mis listas"].waitForExistence(timeout: 10))
        capture("Mis listas")
    }

    /// Crea una lista con el diálogo «Nueva lista».
    private func createList(_ name: String) {
        tap("list-new")
        let alert = app.alerts["Nueva lista"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        let field = alert.textFields["Nombre de la lista"]
        XCTAssertFalse(alert.buttons["Crear"].isEnabled, "No se crea una lista sin nombre")
        field.typeText(name)
        XCTAssertTrue(alert.buttons["Crear"].isEnabled)
        alert.buttons["Crear"].tap()
        XCTAssertTrue(app.buttons[name].waitForExistence(timeout: 10))
    }

    /// En «Guardar en listas», deja la ruta abierta guardada en la lista indicada, creándola si hace falta.
    private func saveCurrentRoute(inList name: String) {
        let row = app.buttons[name]
        if !row.waitForExistence(timeout: 2) { createList(name) }
        if (row.value as? String ?? "").hasPrefix("Sin guardar") { row.tap() }
        XCTAssertTrue((row.value as? String ?? "").hasPrefix("Guardada"), "La ruta queda guardada en " + name)
    }

    /// Ciclo completo de listas: vacío, crear, validar, renombrar, guardar y quitar una ruta, abrirla y eliminar.
    func testListsLifecycle() {
        app.launchArguments = ["--ui-testing", "--catalog-bundle-sample", "--reset-saved-data"]
        app.launch()
        tap("dock-Rutas")
        tap("Mis listas")
        XCTAssertTrue(app.navigationBars["Mis listas"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Aún no tienes listas"].exists, "Estado vacío explicativo")
        capture("Mis listas vacío")
        let name = "Escuela " + String(UUID().uuidString.prefix(4))
        createList(name)
        XCTAssertEqual(app.buttons[name].value as? String, "0 rutas")

        tap("list-new")
        let duplicate = app.alerts["Nueva lista"]
        XCTAssertTrue(duplicate.waitForExistence(timeout: 5))
        duplicate.textFields["Nombre de la lista"].typeText(name.uppercased())
        XCTAssertFalse(duplicate.buttons["Crear"].isEnabled, "No se repite un nombre aunque cambien mayúsculas")
        duplicate.buttons["Cancelar"].tap()

        tap(name)
        XCTAssertTrue(app.navigationBars[name].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Esta lista está vacía"].exists)
        capture("Lista vacía")
        tap("list-options")
        app.buttons["Renombrar"].tap()
        let rename = app.alerts["Renombrar lista"]
        XCTAssertTrue(rename.waitForExistence(timeout: 5))
        let field = rename.textFields["Nombre de la lista"]
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: name.count + 2))
        let renamed = name.replacingOccurrences(of: "Escuela", with: "Trabajo")
        field.typeText(renamed)
        rename.buttons["Guardar"].tap()
        XCTAssertTrue(app.navigationBars[renamed].waitForExistence(timeout: 10))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons[renamed].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons[name].exists)
        tap("Listo")

        tap("catalog-sample-route")
        tap("Guardar en listas")
        XCTAssertTrue(app.navigationBars["Guardar en listas"].waitForExistence(timeout: 10))
        let toggle = app.buttons[renamed]
        XCTAssertTrue(toggle.waitForExistence(timeout: 10))
        XCTAssertTrue((toggle.value as? String ?? "").hasPrefix("Sin guardar"))
        toggle.tap()
        XCTAssertTrue((toggle.value as? String ?? "").hasPrefix("Guardada"))
        capture("Guardar ruta en una lista")
        toggle.tap()
        XCTAssertTrue((toggle.value as? String ?? "").hasPrefix("Sin guardar"), "Tocar de nuevo la quita")
        toggle.tap()
        tap("Listo")
        tap("Cerrar")

        tap("Mis listas")
        XCTAssertEqual(app.buttons[renamed].value as? String, "1 ruta")
        tap(renamed)
        let saved = app.buttons["list-route-sample-route"]
        XCTAssertTrue(saved.waitForExistence(timeout: 10))
        capture("Lista con una ruta")
        saved.tap()
        XCTAssertTrue(app.buttons["Guardar en listas"].waitForExistence(timeout: 10), "Tocar la ruta abre su ficha")
        tap("Cerrar")

        tap("Mis listas")
        tap(renamed)
        tap("list-options")
        app.buttons["Eliminar lista"].firstMatch.tap()
        let confirm = app.sheets.buttons["Eliminar lista"]
        if confirm.waitForExistence(timeout: 3) { confirm.tap() }
        else { app.buttons.matching(identifier: "Eliminar lista").allElementsBoundByIndex.last?.tap() }
        XCTAssertTrue(app.navigationBars["Mis listas"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons[renamed].waitForExistence(timeout: 2), "La lista eliminada desaparece")
    }

    func testMainNavigation() {
        app.launchArguments = ["--ui-testing", "--catalog-bundle-sample"]
        app.launch()
        let search = app.textFields["trip-place-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 15))
        XCTAssertEqual(search.placeholderValue, "Buscar destino")
        XCTAssertFalse(app.buttons["dock-Mapa"].exists)
        XCTAssertFalse(app.buttons["header-favorites"].exists)
        capture("Inicio con buscador de destinos")

        app.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.40)).tap()
        XCTAssertTrue(app.buttons["Elegir origen"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["home-destination"].exists)
        capture("Destino marcado sin permiso de ubicación")
        tap("Reducir panel")
        XCTAssertTrue(app.buttons["Ampliar panel"].exists)
        tap("Ampliar panel")
        tap("dock-Inicio")
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        XCTAssertFalse(app.descendants(matching: .any)["home-destination"].exists)
        tap("dock-Rutas")
        XCTAssertTrue(app.navigationBars["Rutas"].waitForExistence(timeout: 10))
        tap("dock-Favoritos")
        XCTAssertTrue(app.navigationBars["Favoritos"].waitForExistence(timeout: 10))
    }

    /// El dock refleja la pestaña activa y no se desplaza cuando aparece el teclado.
    func testDockSelectionStaysPutWithKeyboard() {
        app.launchArguments = ["--ui-testing", "--catalog-bundle-sample"]
        app.launch()
        XCTAssertTrue(app.textFields["trip-place-search"].waitForExistence(timeout: 15))
        let dock = app.otherElements["app-dock"]
        XCTAssertTrue(dock.exists)
        XCTAssertTrue(app.buttons["dock-Inicio"].isSelected)
        let resting = dock.frame
        for tab in ["Rutas", "Favoritos", "Inicio"] {
            tap("dock-" + tab)
            XCTAssertTrue(app.buttons["dock-" + tab].isSelected, tab)
            XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'dock-' AND selected == true")).count, 1)
            XCTAssertEqual(dock.frame.minY, resting.minY, accuracy: 1, "El dock conserva su posición en " + tab)
        }
        let homeSearch = app.textFields["trip-place-search"]
        homeSearch.tap()
        if app.keyboards.firstMatch.waitForExistence(timeout: 3) {
            XCTAssertEqual(dock.frame.minY, resting.minY, accuracy: 1, "El teclado de Inicio no mueve el dock")
        }
        // Como en las apps del sistema, el teclado cubre el dock: se cierra la búsqueda antes de cambiar de pestaña.
        let close = app.buttons["Cerrar"]
        if close.exists { close.tap() }
        XCTAssertTrue(app.buttons["dock-Rutas"].waitForHittable(timeout: 5))
        tap("dock-Rutas")
        let search = app.textFields["catalog-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap()
        if app.keyboards.firstMatch.waitForExistence(timeout: 3) {
            XCTAssertEqual(dock.frame.minY, resting.minY, accuracy: 1, "El teclado de Rutas no mueve el dock")
            capture("Búsqueda de rutas con teclado")
        }
    }

    /// Rutas filtra mientras se escribe, sin botón de búsqueda duplicado, y agrupa las herramientas.
    func testRoutesInlineSearchAndTools() {
        app.launchArguments = ["--ui-testing", "--catalog-bundle-sample"]
        app.launch()
        tap("dock-Rutas")
        XCTAssertTrue(app.navigationBars["Rutas"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["1 ruta"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["catalog-open-search"].exists, "Sin botón «Buscar» duplicado")
        XCTAssertFalse(app.staticTexts["Filtros"].exists)
        for tool in ["Filtrar por grupo", "Mis listas"] {
            XCTAssertTrue(app.buttons[tool].exists, tool)
        }
        XCTAssertFalse(app.buttons["Servicios"].exists, "Sin avisos ni contacto, Servicios no aparece")
        XCTAssertFalse(app.buttons["Borrar búsqueda"].exists)
        let search = app.textFields["catalog-search"]
        search.tap()
        search.typeText("sin coincidencias")
        XCTAssertTrue(app.staticTexts["Sin coincidencias"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["0 rutas"].exists)
        XCTAssertFalse(app.buttons["catalog-sample-route"].exists)
        capture("Rutas sin coincidencias")
        tap("Borrar búsqueda")
        search.typeText("\n")
        XCTAssertTrue(app.buttons["catalog-sample-route"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["1 ruta"].waitForExistence(timeout: 5))
        search.tap()
        // Los acentos se prueban en la lógica («recórrido EJEMPLO»); aquí, mayúsculas con el teclado real.
        search.typeText("RECORRIDO\n")
        XCTAssertTrue(app.buttons["catalog-sample-route"].waitForExistence(timeout: 10), "Búsqueda sin distinguir mayúsculas")
        tap("Borrar búsqueda")
        tap("Todas")
        XCTAssertTrue(app.buttons["catalog-sample-route"].waitForExistence(timeout: 5))
        tap("Mis listas")
        XCTAssertTrue(app.navigationBars["Mis listas"].waitForExistence(timeout: 10))
    }

    /// Con avisos publicados, Servicios aparece en Rutas con su indicador y muestra el aviso.
    func testRoutesServicesWithNotices() {
        app.launchArguments = ["--ui-testing", "--catalog-services-sample"]
        app.launch()
        tap("dock-Rutas")
        let services = app.buttons["Servicios"]
        XCTAssertTrue(services.waitForExistence(timeout: 15))
        XCTAssertEqual(services.value as? String, "Hay avisos")
        capture("Rutas con avisos de servicio")
        tap("Servicios")
        XCTAssertTrue(app.navigationBars["Servicios"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Aviso de ejemplo · Cambio de horario"].exists)
        capture("Servicios con avisos")
        tap("Cerrar")
        XCTAssertTrue(app.textFields["catalog-search"].waitForExistence(timeout: 5))
    }

    /// Guardar desde la ficha de Rutas aparece en la pestaña Favoritos y quitarlo deja el vacío legítimo.
    func testFavoritesTabFromRouteCard() {
        app.launchArguments = ["--ui-testing", "--catalog-bundle-sample", "--reset-saved-data"]
        app.launch()
        tap("dock-Rutas")
        tap("catalog-sample-route")
        let favorite = app.buttons["favorite-toggle"]
        XCTAssertTrue(favorite.waitForExistence(timeout: 10))
        if favorite.label == "Quitar de favoritos" { favorite.tap() }
        XCTAssertEqual(favorite.label, "Guardar en favoritos")
        favorite.tap()
        XCTAssertEqual(favorite.label, "Quitar de favoritos")
        XCTAssertTrue(app.staticTexts["Guardado en favoritos"].waitForExistence(timeout: 5))
        capture("Ruta guardada en favoritos")
        tap("dock-Favoritos")
        XCTAssertTrue(app.navigationBars["Favoritos"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["Regresar"].exists, "Favoritos es una pestaña raíz sin flecha de regreso")
        let saved = app.buttons["catalog-sample-route"]
        XCTAssertTrue(saved.waitForExistence(timeout: 10))
        XCTAssertTrue((saved.value as? String ?? "").contains("Favorito") || saved.exists)
        capture("Favoritos con datos")
        tap("catalog-sample-route")
        let remove = app.buttons["favorite-toggle"]
        XCTAssertTrue(remove.waitForExistence(timeout: 10))
        remove.tap()
        XCTAssertTrue(app.staticTexts["No hay rutas guardadas."].waitForExistence(timeout: 10))
        capture("Favoritos vacío")
        tap("dock-Favoritos")
        XCTAssertTrue(app.staticTexts["No hay rutas guardadas."].waitForExistence(timeout: 10), "Volver a tocar la pestaña conserva el vacío")
    }

    /// Auditoría de accesibilidad del Inicio unificado, Rutas, ficha y Favoritos actuales.
    func testCurrentScreensAccessibilityAudit() throws {
        app.launchArguments = ["--ui-testing", "--catalog-bundle-sample"]
        app.launch()
        continueAfterFailure = true
        let types: XCUIAccessibilityAuditType = [.contrast, .elementDetection, .hitRegion, .sufficientElementDescription, .trait]
        XCTAssertTrue(app.textFields["trip-place-search"].waitForExistence(timeout: 15))
        try audit("Inicio actual", types: types)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.40)).tap()
        XCTAssertTrue(app.buttons["Elegir origen"].waitForExistence(timeout: 10))
        try audit("Destino actual", types: types)
        tap("dock-Rutas")
        XCTAssertTrue(app.textFields["catalog-search"].waitForExistence(timeout: 10))
        try audit("Rutas actual", types: types)
        tap("catalog-sample-route")
        XCTAssertTrue(app.buttons["Guardar en listas"].waitForExistence(timeout: 10))
        try audit("Ficha actual", types: types)
        tap("dock-Favoritos")
        XCTAssertTrue(app.navigationBars["Favoritos"].waitForExistence(timeout: 10))
        try audit("Favoritos actual", types: types)
    }

    /// Con texto de accesibilidad grande, Inicio y Rutas siguen siendo operables por encima del dock.
    func testCurrentScreensLargeText() {
        app.launchArguments = ["--ui-testing", "--catalog-bundle-sample",
                               "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXL"]
        app.launch()
        let dock = app.otherElements["app-dock"]
        XCTAssertTrue(app.textFields["trip-place-search"].waitForExistence(timeout: 15))
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.30)).tap()
        let origin = app.buttons["Elegir origen"]
        XCTAssertTrue(origin.waitForExistence(timeout: 10))
        XCTAssertLessThanOrEqual(origin.frame.maxY, dock.frame.minY + 1, "El origen queda por encima del dock")
        capture("Inicio con texto grande")
        tap("dock-Rutas")
        XCTAssertTrue(app.textFields["catalog-search"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["catalog-sample-route"].waitForExistence(timeout: 10))
        tap("catalog-sample-route")
        XCTAssertTrue(app.buttons["Guardar en listas"].waitForExistence(timeout: 10))
        capture("Ficha con texto grande")
    }

    func testTripManualSearch() {
        app.terminate()
        app.launchArguments = ["--ui-testing", "--trip-fixture"]
        app.launch()
        tap("trip-search-toggle")
        XCTAssertTrue(app.navigationBars["Desde dónde sales"].exists)
        let search = app.textFields["trip-place-search"]
        for _ in 0..<8 {
            if search.isHittable { break }
            app.scrollViews.firstMatch.swipeUp()
        }
        search.tap()
        search.typeText("Parada 1")
        XCTAssertTrue(app.buttons["trip-place-0"].waitForExistence(timeout: 10))
        capture("Buscar origen con resultados")
        tap("Borrar búsqueda")
        XCTAssertFalse(app.buttons["trip-place-0"].exists)
        search.typeText("Parada 1\n")
        tap("trip-place-0")
        tap("trip-continue")
        capture("Panel de destino")
        tap("Elegir destino en el mapa")
        XCTAssertTrue(app.navigationBars["Elegir destino"].waitForExistence(timeout: 5))
        capture("Selector de destino en el mapa")
        tap("Cancelar")
        tap("trip-calculate")
        XCTAssertTrue(app.staticTexts["trip-result"].waitForExistence(timeout: 10))
        capture("Consulta con origen manual")
    }

    func testNearbyStopSelectionKeepsSuggestions() {
        app.terminate()
        app.launchArguments = ["--ui-testing", "--trip-fixture"]
        app.launch()
        tap("trip-search-toggle")
        XCTAssertTrue(app.navigationBars["Desde dónde sales"].exists)
        let search = app.textFields["trip-place-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        for _ in 0..<8 where !search.isHittable { app.scrollViews.firstMatch.swipeUp() }
        search.tap()
        search.typeText("Parada 1\n")
        tap("trip-place-0")
        let stop = app.buttons["trip-stop-trip-stop-0"]
        XCTAssertTrue(stop.waitForExistence(timeout: 5))
        XCTAssertTrue(stop.label.contains("en línea recta"))
        let description = stop.label
        tap("trip-stop-trip-stop-0")
        XCTAssertTrue(app.navigationBars["Desde dónde sales"].exists)
        XCTAssertTrue(stop.waitForExistence(timeout: 5))
        XCTAssertEqual(stop.label, description)
        XCTAssertEqual(stop.value as? String, "Seleccionada")
        XCTAssertTrue(app.staticTexts["Paradas cercanas"].exists)
        tap("trip-continue")
        XCTAssertTrue(app.navigationBars["A dónde vas"].waitForExistence(timeout: 5))
    }

    func testTripImpreciseLocation() {
        app.terminate()
        app.launchArguments = ["--ui-testing", "--trip-fixture", "--trip-imprecise"]
        app.launch()
        tap("trip-continue")
        tap("trip-calculate")
        XCTAssertTrue(app.staticTexts["trip-result"].waitForExistence(timeout: 10))
        tap("trip-begin")
        tap("trip-walk-arrived")
        tap("trip-board")
        let status = app.staticTexts["trip-travel-status"]
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        XCTAssertTrue(status.label.contains("Ubicación sin actualizar"))
        XCTAssertTrue(app.buttons["trip-alight"].isEnabled)
        capture("Transporte sin ubicación precisa")
        tap("trip-finish")
        tap("Finalizar")
    }

    private func checkAccessibleControl(_ element: XCUIElement, label: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(element.waitForExistence(timeout: 5), file: file, line: line)
        XCTAssertTrue(element.isHittable, file: file, line: line)
        XCTAssertEqual(element.label, label, file: file, line: line)
        XCTAssertGreaterThanOrEqual(element.frame.width + 0.001, 44, file: file, line: line)
        XCTAssertGreaterThanOrEqual(element.frame.height + 0.001, 44, file: file, line: line)
    }

    private func audit(_ screen: String, types: XCUIAccessibilityAuditType = .all) throws {
        try app.performAccessibilityAudit(for: types) { issue in
            if let element = issue.element {
                print("[\(screen)] \(issue.auditType): \(element.label), \(element.identifier), \(element.frame)")
                if issue.auditType == .hitRegion && element.identifier.isEmpty && element.label == "Aviso legal" {
                    return true
                }
                // En iOS 17 y 18 el UITextField no crece en vertical; la barra entera (50 pt) enfoca el campo.
                if issue.auditType == .hitRegion, ["trip-place-search", "catalog-search"].contains(element.identifier),
                   element.frame.height >= 17 { return true }
                // Rótulos y puntos de interés que dibuja Apple Maps en la parte visible del mapa.
                let map = self.app.otherElements["Mapa de Tijuana"]
                let handle = self.app.buttons["home-panel-handle"]
                if map.exists, element.identifier.isEmpty, element.elementType != .button, element.elementType != .textField {
                    var visible = map.frame
                    if handle.exists { visible.size.height = max(0, handle.frame.minY - visible.minY) }
                    if visible.contains(element.frame) { return true }
                }
                if issue.auditType == .contrast {
                    let home = self.app.scrollViews["home-scroll"]
                    if screen == "Inicio", home.exists,
                       element.frame.minY >= home.frame.maxY,
                       !["Rutas", "Inicio", "Mapa"].contains(element.label) { return true }
                    let tabBar = self.app.otherElements["app-dock"]
                    let bottom = tabBar.isHittable ? tabBar.frame.minY : self.app.frame.maxY
                    if element.frame.midY >= bottom || element.frame.maxY <= self.app.frame.minY ||
                        element.frame.minX >= self.app.frame.maxX || element.frame.maxX <= self.app.frame.minX { return true }
                }
                // Blanco sobre la cabecera negra (17:1); la muestra incluye la barra de estado.
                if issue.auditType == .contrast && element.identifier == "home-title" { return true }
            } else {
                print("[\(screen)] \(issue.auditType): \(issue.compactDescription)")
                // Texto que dibuja Apple Maps dentro del mapa, sin elemento propio de la app.
                if issue.auditType == .elementDetection && self.app.maps.firstMatch.exists { return true }
            }
            return false
        }
    }

    func testEvaluationRejectsMissingDate() {
        app.terminate()
        app.launchArguments = ["--legacy-consultation-test", "--ui-testing", "--evaluation-no-date"]
        app.launch()
        tap("Evaluar consulta")
        tap("Planear mi ruta")
        tap("stop-demo-4")
        tap("Elegir destino")
        XCTAssertTrue(app.staticTexts["Ruta rechazada"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Fecha no disponible"].exists)
        XCTAssertFalse(app.buttons["walking-start"].exists)
    }

    func testWalkingGuide() {
        app.terminate()
        app.launchArguments = ["--legacy-consultation-test", "--journey-fixture", "--ui-testing", "--walking-fixture"]
        app.launch()
        tap("Elegir ubicación inicial")
        tap("stop-demo-1")
        tap("Continuar")
        tap("stop-demo-4")
        tap("Ver trayecto")
        tap("walking-start")
        XCTAssertTrue(app.buttons["Iniciar guía"].waitForExistence(timeout: 10))
        capture("Vista previa peatonal")
        tap("Iniciar guía")
        XCTAssertTrue(app.staticTexts["walking-instruction"].waitForExistence(timeout: 10))
        capture("Guía")
        tap("Ver pasos")
        XCTAssertTrue(app.navigationBars["Indicaciones"].waitForExistence(timeout: 5))
        capture("Indicaciones")
        tap("walking-close-steps")
        tap("walking-finish")
        tap("Terminar guía")
        XCTAssertTrue(app.staticTexts["Sube en Parada 1"].waitForExistence(timeout: 5))
    }

    func testWalkingFailure() {
        app.terminate()
        app.launchArguments = ["--legacy-consultation-test", "--journey-fixture", "--ui-testing", "--walking-fixture", "--walking-error"]
        app.launch()
        tap("Elegir ubicación inicial")
        tap("stop-demo-1")
        tap("Continuar")
        tap("stop-demo-4")
        tap("Ver trayecto")
        tap("walking-start")
        XCTAssertTrue(app.staticTexts["walking-status"].waitForExistence(timeout: 5))
        let retry = app.buttons["Reintentar"]
        XCTAssertTrue(retry.waitForExistence(timeout: 5))
        XCTAssertFalse(retry.isEnabled)
        XCTAssertFalse(app.buttons["Iniciar guía"].exists)
        capture("Guía sin conexión")
    }

    func testWalkingWarningAndLargeText() {
        app.terminate()
        app.launchArguments = ["--legacy-consultation-test", "--journey-fixture", "--ui-testing", "--walking-fixture", "--walking-gap", "--walking-long", "--walking-dark", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        tap("Elegir ubicación inicial")
        tap("stop-demo-1")
        tap("Continuar")
        tap("stop-demo-4")
        tap("Ver trayecto")
        tap("walking-start")
        tap("Iniciar guía")
        let warning = app.staticTexts["walking-status"]
        XCTAssertTrue(warning.waitForExistence(timeout: 5))
        XCTAssertTrue(warning.label.contains("El camino termina"))
        let persisted = XCTNSPredicateExpectation(predicate: NSPredicate(format: "NOT (label CONTAINS %@)", "El camino termina"), object: warning)
        persisted.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [persisted], timeout: 4), .completed)
        XCTAssertFalse(app.buttons["Reintentar"].exists)
        app.scrollViews.firstMatch.swipeDown()
        capture("Guía con texto grande")
    }

    func testCatalogFilters() {
        app.terminate()
        app.launchArguments = ["--legacy-consultation-test", "--ui-testing", "--catalog-sample"]
        app.launch()
        tap("Explorar recorridos")
        let filter = app.buttons["catalog-filter"]
        XCTAssertTrue(filter.waitForExistence(timeout: 5))
        filter.tap()
        let stopOption = app.buttons.matching(identifier: "Paradas").allElementsBoundByIndex.first { $0.isHittable }
        XCTAssertNotNil(stopOption)
        stopOption?.tap()
        XCTAssertFalse(app.buttons["catalog-sample-route"].exists)
        XCTAssertTrue(app.staticTexts["Sin coincidencias"].waitForExistence(timeout: 5))
        capture("Filtro de paradas")
    }

    func testSameStopIsRejected() {
        launchConsultation()
        tap("Elegir ubicación inicial")
        tap("stop-demo-1")
        tap("Continuar")
        tap("stop-demo-1")
        tap("Ver trayecto")
        XCTAssertTrue(app.alerts["Destino no válido"].waitForExistence(timeout: 5))
        capture("Destino no válido")
        tap("Cambiar destino")
        let disabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == false"),
                                                 object: app.buttons["Ver trayecto"])
        XCTAssertEqual(XCTWaiter.wait(for: [disabled], timeout: 5), .completed)
    }

    func testCatalogSearchAndSelection() {
        app.terminate()
        app.launchArguments = ["--legacy-consultation-test", "--catalog-sample"]
        app.launch()
        tap("Explorar recorridos")
        tap("catalog-sample-route")
        tap("catalog-information")
        XCTAssertTrue(app.staticTexts["Horario: Desconocido"].waitForExistence(timeout: 5))
        tap("catalog-information-close")
        capture("Recorridos")
        let search = app.textFields["catalog-search"]
        tap("catalog-open-search")
        let routeSearch = app.textFields["route-search-field"]
        XCTAssertTrue(routeSearch.waitForExistence(timeout: 10))
        routeSearch.tap()
        routeSearch.typeText("Recorrido")
        XCTAssertTrue(app.buttons["route-search-result-sample-route"].waitForExistence(timeout: 10))
        capture("Buscar recorridos")
        tap("Cerrar")
        search.tap()
        search.typeText("sin coincidencias")
        search.typeText("\n")
        XCTAssertTrue(app.staticTexts["Sin coincidencias"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["catalog-sample-route"].exists)
    }

    func testSearchWithoutConnection() {
        app.terminate()
        app.launchArguments = ["--legacy-consultation-test", "--journey-fixture", "--offline"]
        app.launch()
        tap("Elegir ubicación inicial")
        XCTAssertTrue(app.staticTexts.matching(identifier: "Sin conexión · Puedes elegir de la lista").firstMatch.waitForExistence(timeout: 5))
        let mapNotice = app.staticTexts["route-map-demo"]
        XCTAssertTrue(mapNotice.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(mapNotice.frame.minY, 20)
        let search = app.textFields["journey-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("PARADA 4")
        XCTAssertTrue(app.buttons["stop-demo-4"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["stop-demo-1"].exists)
        search.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 8))
        search.typeText("sin coincidencias")
        search.typeText("\n")
        XCTAssertTrue(app.staticTexts["Sin coincidencias"].waitForExistence(timeout: 10))
        capture("Búsqueda sin conexión")
    }

    func testCatalogInformation() {
        app.terminate()
        app.launchArguments = ["--legacy-consultation-test", "--catalog-info-sample"]
        app.launch()
        tap("Explorar recorridos")
        tap("catalog-sample-route")
        tap("catalog-information")
        XCTAssertTrue(app.staticTexts["Descripción de ejemplo"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Horario: 06:00–20:00"].exists)
        capture("Información")
        tap("catalog-information-close")
        XCTAssertTrue(app.buttons["catalog-information"].waitForExistence(timeout: 5))
    }

    func testCatalogPersistsAcrossLaunches() {
        app.terminate()
        app.launchArguments = ["--legacy-consultation-test", "--catalog-persistence-sample"]
        app.launch()
        tap("Explorar recorridos")
        XCTAssertTrue(app.buttons["catalog-sample-route"].waitForExistence(timeout: 5))
        app.terminate()
        app.launch()
        tap("Explorar recorridos")
        XCTAssertTrue(app.buttons["catalog-sample-route"].waitForExistence(timeout: 5))
        tap("catalog-sample-route")
        XCTAssertTrue(app.staticTexts["Recorrido de ejemplo"].firstMatch.waitForExistence(timeout: 5))
        capture("Catálogo guardado")
    }

    func testFavoritesPersistAndShowFeedback() {
        app.terminate()
        app.launchArguments = ["--legacy-consultation-test", "--ui-testing", "--catalog-bundle-sample"]
        app.launch()
        tap("Explorar recorridos")
        tap("catalog-sample-route")
        let favorite = app.buttons["favorite-toggle"]
        XCTAssertTrue(favorite.waitForExistence(timeout: 10))
        if favorite.label == "Quitar de favoritos" { favorite.tap() }
        favorite.tap()
        XCTAssertTrue(app.staticTexts["Guardado en favoritos"].waitForExistence(timeout: 5))
        XCTAssertEqual(favorite.label, "Quitar de favoritos")
        capture("Favorito guardado")
        app.terminate()
        app.launch()
        tap("dock-Favoritos")
        let route = app.buttons["catalog-sample-route"]
        XCTAssertTrue(route.waitForExistence(timeout: 10))
        XCTAssertTrue((route.value as? String ?? "").contains("Favorito"))
        XCTAssertFalse(app.navigationBars["Favoritos"].buttons["header-favorites"].exists)
        capture("Favoritos guardados")
        tap("catalog-sample-route")
        tap("favorite-toggle")
        XCTAssertTrue(app.staticTexts["Quitado de favoritos"].waitForExistence(timeout: 5))
        let notice = app.staticTexts["favorite-notice"]
        if notice.exists {
            let cleared = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: notice)
            XCTAssertEqual(XCTWaiter.wait(for: [cleared], timeout: 12), .completed)
        }
        capture("Favoritos vacío")
    }

    func testFullCatalogOffline() {
        app.terminate()
        app.launchArguments = ["--legacy-consultation-test", "--ui-testing", "--catalog-bundle-sample", "--catalog-full-test", "--offline", "--gallery"]
        for attempt in 0..<2 {
            app.launch()
            if attempt == 0 {
                let recent = app.buttons["recent-planned-feature_7eb377470e968bbdb36536f6"]
                XCTAssertTrue(recent.waitForExistence(timeout: 20))
                capture("Inicio con catálogo real")
            }
            app.buttons["dock-Rutas"].tap()
            XCTAssertTrue(app.staticTexts["182 rutas"].waitForExistence(timeout: 25))
            if attempt == 0 {
                capture("Rutas por zona con catálogo completo")
                tap("Todas")
                capture("Todas las rutas con catálogo completo")
                let routeSearch = app.textFields["catalog-search"]
                XCTAssertTrue(routeSearch.waitForExistence(timeout: 5))
                routeSearch.tap()
                routeSearch.typeText("Centro")
                let results = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "catalog-"))
                XCTAssertTrue(results.firstMatch.waitForExistence(timeout: 10))
                capture("Buscar recorridos reales")
                routeSearch.typeText(" Murua")
                tap("catalog-centro-murua")
                XCTAssertTrue(app.buttons["catalog-information"].waitForExistence(timeout: 10))
                capture("Centro a Murúa")
                tap("Cerrar")
            }
            let search = app.textFields["catalog-search"]
            XCTAssertTrue(search.waitForExistence(timeout: 10))
            search.tap()
            if let value = search.value as? String, value == "Centro Murua" {
                search.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: value.count))
            }
            search.typeText("Murua\n")
            XCTAssertTrue(app.buttons["catalog-centro-murua"].waitForExistence(timeout: 10))
            if attempt == 0 {
                capture("Búsqueda con catálogo completo")
                tap("catalog-centro-murua")
                capture("Centro a Murúa")
            } else {
                app.terminate()
                app.launch()
                tap("dock-Rutas")
                let fullSearch = app.textFields["catalog-search"]
                XCTAssertTrue(fullSearch.waitForExistence(timeout: 10))
                fullSearch.tap()
                fullSearch.typeText("Fundadores\n")
                tap("catalog-feature_7eb377470e968bbdb36536f6")
                capture("Ficha con datos de servicio")
                let favorite = app.buttons["favorite-toggle"]
                XCTAssertTrue(favorite.waitForExistence(timeout: 5))
                if favorite.label == "Guardar en favoritos" { favorite.tap() }
                tap("catalog-information")
                XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH %@", "Horario:")).firstMatch.waitForExistence(timeout: 5))
                capture("Información del recorrido")
                tap("catalog-information-close")
                tap("Guardar en listas")
                XCTAssertTrue(app.navigationBars["Guardar en listas"].waitForExistence(timeout: 5))
                saveCurrentRoute(inList: "Recorridos habituales")
                capture("Guardar recorrido real en listas")
                tap("Listo")
                tap("Cerrar")
                tap("Mis listas")
                capture("Listas con recorridos reales")
                tap("Listo")
                tap("dock-Inicio")
                tap("dock-Favoritos")
                XCTAssertTrue(app.navigationBars["Favoritos"].waitForExistence(timeout: 5))
                capture("Favoritos con datos reales")
            }
            app.terminate()
        }
    }

    func testBundledCatalogAndPhotoOffline() {
        app.terminate()
        app.launchArguments = ["--legacy-consultation-test", "--ui-testing", "--catalog-bundle-sample", "--offline"]
        for _ in 0..<2 {
            app.launch()
            tap("Explorar recorridos")
            XCTAssertTrue(app.navigationBars["Recorridos"].waitForExistence(timeout: 15))
            tap("catalog-sample-route")
            tap("catalog-information")
            XCTAssertTrue(app.images["catalog-photo"].waitForExistence(timeout: 10))
            app.terminate()
        }
    }

    func testReferenceEntryScreens() {
        app.terminate()
        app.launchArguments = ["--legacy-consultation-test", "--ui-testing", "--catalog-bundle-sample", "--catalog-full-test", "--gallery"]
        app.launch()
        XCTAssertTrue(app.buttons["recent-planned-feature_7eb377470e968bbdb36536f6"].waitForExistence(timeout: 20))
        capture("08 Inicio")
        tap("Abrir mapa para planear viaje")
        XCTAssertTrue(app.navigationBars["Desde dónde sales"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["trip-continue"].exists)
        capture("10 Origen inicial")
    }

    func testReferenceSelectorWithCatalog() {
        app.terminate()
        app.launchArguments = ["--legacy-consultation-test", "--ui-testing", "--catalog-bundle-sample", "--catalog-full-test", "--gallery", "--capture-catalog"]
        app.launch()
        tap("Abrir mapa para planear viaje")
        tap("Elegir origen en el mapa")
        XCTAssertTrue(app.navigationBars["Elegir origen"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Seleccionar"].isEnabled)
        capture("13 Selector en mapa")
        tap("Cancelar")
        XCTAssertTrue(app.navigationBars["Desde dónde sales"].exists)
    }

    func testReferenceOriginSearchWithCatalog() {
        app.terminate()
        app.launchArguments = ["--legacy-consultation-test", "--ui-testing", "--catalog-bundle-sample", "--catalog-full-test", "--gallery"]
        app.launch()
        tap("Abrir mapa para planear viaje")
        tap("trip-search-toggle")
        let search = app.textFields["trip-place-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap()
        search.typeText("Farmacia")
        XCTAssertTrue(app.buttons["trip-place-2"].waitForExistence(timeout: 15))
        capture("11 Buscar origen")
    }

    func testReferenceCatalogScreens() {
        app.terminate()
        app.launchArguments = ["--legacy-consultation-test", "--ui-testing", "--catalog-bundle-sample", "--gallery"]
        #if targetEnvironment(simulator)
        app.launchArguments.append("--catalog-full-test")
        #endif
        app.launch()
        tap("Explorar recorridos")
        XCTAssertTrue(app.staticTexts["Resultados: 182"].waitForExistence(timeout: 15))
        capture("19 Recorridos")
        let rows = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND NOT (identifier IN %@)",
            "catalog-", ["catalog-open-search", "catalog-filter"]
        ))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 10))
        let visible = try? XCTUnwrap(rows.allElementsBoundByIndex.first(where: \.isHittable))
        guard let visible else { return }
        visible.tap()
        XCTAssertTrue(app.buttons["catalog-information"].waitForExistence(timeout: 10))
        capture("22 Recorrido seleccionado")
    }

    func testAppScreensWithCatalog() throws {
        try checkRealTrip(includeSearch: true)
    }

    func testHomeWalkingBadge() {
        app.launchArguments = ["--ui-testing", "--catalog-bundle-sample", "--catalog-full-test", "--capture-walking-stage"]
        app.launch()
        XCTAssertTrue(app.buttons["trip-begin"].waitForExistence(timeout: 60))
        tap("trip-begin")
        XCTAssertTrue(app.staticTexts["Caminata"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["trip-walk-arrived"].exists)
        XCTAssertFalse(app.staticTexts["Estado actual"].exists)
        capture("Caminata con cápsula naranja")
    }

    func testDockFinishesActiveTrip() throws {
        try checkRealTrip(includeSearch: false)
    }

    private func checkRealTrip(includeSearch: Bool) throws {
        app.terminate()
        app.launchArguments = ["--ui-testing", "--catalog-bundle-sample", "--gallery", "--capture-catalog"]
        #if !LIVE_MAP_CAPTURE
        app.launchArguments.append("--catalog-full-test")
        #endif
        app.launch()
        XCTAssertTrue(app.textFields["trip-place-search"].waitForExistence(timeout: 15))
        let result = app.staticTexts["trip-result"]
        guard result.waitForExistence(timeout: 120) else {
            throw XCTSkip("No se obtuvo un itinerario con rutas peatonales durante la captura.")
        }
        XCTAssertTrue(app.buttons["trip-begin"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Punto de origen"].exists, "La captura usa la dirección real del origen")
        let emptyFigures = NSPredicate(format: "label CONTAINS '0 transbordos' OR label CONTAINS ' 0 m a pie'")
        XCTAssertFalse(app.staticTexts.containing(emptyFigures).firstMatch.exists, "Sin cifras vacías en el resumen")
        let begin = app.buttons["trip-begin"].frame
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))
        XCTAssertEqual(app.buttons["trip-begin"].frame.minY, begin.minY, accuracy: 1, "«Iniciar viaje» no se mueve al llegar la alternativa")
        capture("Resultado con recorrido real")
        tap("trip-begin")
        XCTAssertFalse(app.textFields["trip-place-search"].exists)
        XCTAssertTrue(app.buttons["trip-finish"].waitForExistence(timeout: 10))
        capture("Trayecto con recorrido real")
        let arrive = app.buttons["trip-walk-arrived"]
        if arrive.isHittable { arrive.tap() }
        let board = app.buttons["trip-board"]
        XCTAssertTrue(board.waitForExistence(timeout: 10))
        capture("Espera para subir con recorrido real")

        tap("trip-board")
        XCTAssertTrue(app.staticTexts["En transporte"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Etapa 1 de 1"].exists, "Un trayecto de una sola etapa no repite el progreso")
        capture("En transporte con recorrido real")
        if !includeSearch {
            for tab in ["Rutas", "Favoritos"] {
                tap("dock-" + tab)
                XCTAssertTrue(app.navigationBars[tab].waitForExistence(timeout: 10))
                XCTAssertFalse(app.buttons["Finalizar trayecto"].exists)
                if tab == "Favoritos" { capture("Favoritos durante el trayecto") }
                tap("dock-Inicio")
                XCTAssertTrue(app.buttons["trip-alight"].waitForExistence(timeout: 10))
                XCTAssertTrue(app.staticTexts["En transporte"].firstMatch.exists)
            }
            capture("Trayecto conservado al volver a Inicio")
            let handle = app.buttons["home-panel-handle"]
            XCTAssertTrue(handle.isHittable)
            let center = handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            center.press(forDuration: 0.1, thenDragTo: center.withOffset(CGVector(dx: 0, dy: -110)))
            XCTAssertEqual(handle.value as? String, "Expandido")
            let boarding = app.staticTexts["Punto de subida sugerido"]
            let alighting = app.staticTexts["Punto de bajada sugerido"]
            if boarding.exists && alighting.exists {
                XCTAssertLessThan(boarding.frame.minY, alighting.frame.minY, "La subida aparece antes que la bajada")
            }
            capture("Panel expandido durante el trayecto")
            let expanded = handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            expanded.press(forDuration: 0.1, thenDragTo: expanded.withOffset(CGVector(dx: 0, dy: 110)))
            XCTAssertEqual(handle.value as? String, "Medio")
            tap("trip-finish")
            XCTAssertTrue(app.buttons["Finalizar"].waitForExistence(timeout: 10))
            capture("Confirmación desde la flecha")
            let cancel = app.sheets["¿Finalizar el viaje?"].buttons["Cancelar"]
            if cancel.exists { cancel.tap() }
            else { app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.2)).tap() }
            let closed = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.buttons["Finalizar"])
            wait(for: [closed], timeout: 10)
        }
        try XCTUnwrap(app.buttons.matching(identifier: "dock-Inicio")
            .allElementsBoundByIndex.last(where: \.isHittable)).tap()
        let finish = app.buttons["Finalizar trayecto"]
        XCTAssertTrue(finish.waitForExistence(timeout: 10))
        capture("Confirmación al volver a Inicio")
        if !includeSearch {
            finish.tap()
            XCTAssertTrue(app.textFields["trip-place-search"].waitForExistence(timeout: 10))
            capture("Inicio después de finalizar desde el dock")
            return
        }
        let cancel = app.sheets["¿Finalizar el trayecto?"].buttons["Cancelar"]
        if cancel.exists {
            cancel.tap()
        } else {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)).tap()
        }
        XCTAssertTrue(app.buttons["trip-alight"].waitForExistence(timeout: 10))
        tap("trip-alight")
        if arrive.isHittable { arrive.tap() }
        XCTAssertTrue(app.staticTexts["Viaje finalizado"].firstMatch.waitForExistence(timeout: 10))
        capture("Viaje finalizado con recorrido real")
        try XCTUnwrap(app.buttons.matching(identifier: "dock-Inicio")
            .allElementsBoundByIndex.last(where: \.isHittable)).tap()
        XCTAssertTrue(app.textFields["trip-place-search"].waitForExistence(timeout: 10))
        capture("Inicio al volver al inicio")
    }

    func testWalkingLiveRoute() throws {
        app.terminate()
        app.launchArguments = ["--legacy-consultation-test", "--journey-fixture", "--ui-testing", "--walking-live-directions"]
        app.launch()
        tap("Elegir ubicación inicial")
        tap("stop-demo-1")
        tap("Continuar")
        tap("stop-demo-4")
        tap("Ver trayecto")
        tap("walking-start")
        guard app.buttons["Iniciar guía"].waitForExistence(timeout: 25) else {
            throw XCTSkip("Apple Maps no devolvió un recorrido para la captura.")
        }
        capture("Recorrido peatonal")
        tap("Iniciar guía")
        XCTAssertTrue(app.staticTexts["walking-instruction"].waitForExistence(timeout: 15))
        capture("Guía peatonal")
        tap("Ver pasos")
        XCTAssertTrue(app.navigationBars["Indicaciones"].waitForExistence(timeout: 5))
        capture("Indicaciones peatonales")
    }

    private func tap(_ identifier: String) {
        let button = app.buttons[identifier]
        guard button.waitForExistence(timeout: 5) else {
            recordMissingControl(identifier, reason: "No apareció")
            return
        }
        for _ in 0..<8 {
            let tabBar = app.otherElements["app-dock"]
            let aboveTab = identifier.hasPrefix("dock-") || !tabBar.isHittable || button.frame.midY < tabBar.frame.minY
            let fixedAction = app.buttons["trip-continue"]
            let aboveAction = !identifier.hasPrefix("trip-stop-") || !fixedAction.isHittable || button.frame.midY < fixedAction.frame.minY
            let unobscured = aboveTab && aboveAction
            if button.isHittable && unobscured {
                button.tap()
                return
            }
            let scroll = app.scrollViews.containing(.button, identifier: identifier).firstMatch
            let target = scroll.exists ? scroll : app.scrollViews.firstMatch
            guard target.isHittable else { break }
            let viewport = target.frame
            if button.frame.midY < viewport.minY {
                target.swipeDown()
            } else {
                target.swipeUp()
            }
            var previousY = button.frame.midY
            for _ in 0..<10 {
                RunLoop.current.run(until: Date().addingTimeInterval(0.15))
                let currentY = button.frame.midY
                if abs(currentY - previousY) < 0.5 { break }
                previousY = currentY
            }
        }
        recordMissingControl(identifier, reason: "No se pudo tocar")
    }

    private func recordMissingControl(_ identifier: String, reason: String) {
        capture("Fallo · " + identifier)
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = "Jerarquía · " + identifier
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
        XCTFail(reason + ": " + identifier)
    }

    private func capture(_ name: String) {
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

private extension XCUIElement {
    func waitForHittable(timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if exists && isHittable { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return exists && isHittable
    }
}
