import XCTest

final class JourneyTests: XCTestCase {
    private let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launchConsultation() {
        app.launchArguments = ["--ui-testing", "--journey-fixture"]
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
        app.launchArguments = ["--journey-fixture", "--ui-testing", "--catalog-info-sample"]
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
        app.launchArguments = ["--journey-fixture", "--ui-testing", "--walking-fixture"]
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
        app.launchArguments = ["--journey-fixture", "--ui-testing", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategory" + size]
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
        app.launchArguments = ["--ui-testing", "--catalog-pale-sample"] + (dark ? ["--catalog-dark"] : [])
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
        app.launchArguments = ["--ui-testing", "--catalog-bundle-sample", "--catalog-recent-sample"]
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
        app.launchArguments = ["--ui-testing"]
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
        capture("Ficha de ruta")
        tap("Guardar en listas")
        XCTAssertTrue(app.navigationBars["Guardar en listas"].waitForExistence(timeout: 10))
        let name = "Lista " + String(UUID().uuidString.prefix(8))
        let field = app.textFields["Nombre de la lista"]
        field.tap()
        field.typeText(name)
        tap("Crear lista")
        XCTAssertTrue(app.buttons[name].waitForExistence(timeout: 10))
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

    func testMainNavigation() {
        app.terminate()
        app.launchArguments = ["--ui-testing", "--catalog-bundle-sample"]
        app.launch()
        XCTAssertTrue(app.buttons["dock-Inicio"].waitForExistence(timeout: 10))
        app.buttons["dock-Mapa"].tap()
        let mapStart = app.buttons["map-start"]
        XCTAssertTrue(mapStart.waitForExistence(timeout: 15))
        let mapDockButton = app.buttons["dock-Mapa"]
        XCTAssertTrue(mapDockButton.isHittable)
        XCTAssertLessThan(mapStart.frame.maxY, mapDockButton.frame.minY)
        let cityMap = app.maps.firstMatch
        if cityMap.exists { XCTAssertGreaterThanOrEqual(cityMap.frame.maxY + 2, mapDockButton.frame.maxY) }
        XCTAssertTrue(app.buttons["Favoritos"].isHittable)
        capture("Mapa")
        app.buttons["dock-Inicio"].tap()
        tap("Abrir mapa para planear viaje")
        XCTAssertTrue(app.navigationBars["Desde dónde sales"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["header-favorites"].isHittable)
        XCTAssertFalse(app.buttons["trip-continue"].exists)
        capture("Origen inicial desde Inicio")
        tap("Regresar")
        app.buttons["dock-Rutas"].tap()
        XCTAssertTrue(app.navigationBars["Rutas"].waitForExistence(timeout: 10))
        app.buttons["dock-Mapa"].tap()
        XCTAssertTrue(app.buttons["map-start"].waitForExistence(timeout: 15))
        tap("map-start")
        XCTAssertTrue(app.navigationBars["Desde dónde sales"].waitForExistence(timeout: 10))
        XCTAssertLessThanOrEqual(app.scrollViews["trip-panel"].frame.maxY, app.otherElements["app-dock"].frame.minY + 1)
        capture("Panel de origen")
        tap("trip-search-toggle")
        let search = app.textFields["trip-place-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        for _ in 0..<8 where !search.isHittable { app.scrollViews.firstMatch.swipeUp() }
        XCTAssertTrue(search.isHittable)
        search.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        capture("Buscar origen")
        tap("Cerrar")
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            !search.exists && !self.app.keyboards.firstMatch.exists
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 10), .completed)
        tap("dock-Inicio")
        XCTAssertTrue(app.buttons["Explorar recorridos"].waitForExistence(timeout: 10))
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
            } else {
                print("[\(screen)] \(issue.auditType): \(issue.compactDescription)")
            }
            return false
        }
    }

    func testEvaluationRejectsMissingDate() {
        app.terminate()
        app.launchArguments = ["--ui-testing", "--evaluation-no-date"]
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
        app.launchArguments = ["--journey-fixture", "--ui-testing", "--walking-fixture"]
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
        app.launchArguments = ["--journey-fixture", "--ui-testing", "--walking-fixture", "--walking-error"]
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
        app.launchArguments = ["--journey-fixture", "--ui-testing", "--walking-fixture", "--walking-gap", "--walking-long", "--walking-dark", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
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
        app.launchArguments = ["--ui-testing", "--catalog-sample"]
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
        app.launchArguments = ["--catalog-sample"]
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
        app.launchArguments = ["--journey-fixture", "--offline"]
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
        app.launchArguments = ["--catalog-info-sample"]
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
        app.launchArguments = ["--catalog-persistence-sample"]
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
        app.launchArguments = ["--ui-testing", "--catalog-bundle-sample"]
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
        tap("Favoritos")
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
        app.launchArguments = ["--ui-testing", "--catalog-bundle-sample", "--catalog-full-test", "--offline", "--gallery"]
        for attempt in 0..<2 {
            app.launch()
            if attempt == 0 {
                let recent = app.buttons["recent-planned-feature_7eb377470e968bbdb36536f6"]
                XCTAssertTrue(recent.waitForExistence(timeout: 20))
                capture("Inicio con catálogo real")
            }
            app.buttons["dock-Rutas"].tap()
            XCTAssertTrue(app.staticTexts["Resultados: 182"].waitForExistence(timeout: 25))
            if attempt == 0 {
                capture("Rutas por zona con catálogo completo")
                tap("Todas")
                capture("Todas las rutas con catálogo completo")
                tap("catalog-open-search")
                let routeSearch = app.textFields["route-search-field"]
                XCTAssertTrue(routeSearch.waitForExistence(timeout: 5))
                routeSearch.tap()
                routeSearch.typeText("Centro")
                let results = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "route-search-result-"))
                XCTAssertTrue(results.firstMatch.waitForExistence(timeout: 10))
                capture("Buscar recorridos reales")
                routeSearch.typeText(" Murua")
                tap("route-search-result-centro-murua")
                capture("Centro a Murúa")
                tap("Cerrar")
            }
            let search = app.textFields["catalog-search"]
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
                let listName = app.textFields["Nombre de la lista"]
                XCTAssertTrue(listName.waitForExistence(timeout: 5))
                listName.tap()
                listName.typeText("Recorridos habituales")
                tap("Crear lista")
                capture("Guardar recorrido real en listas")
                tap("Listo")
                tap("Cerrar")
                tap("Mis listas")
                capture("Listas con recorridos reales")
                tap("Listo")
                tap("dock-Inicio")
                tap("Favoritos")
                XCTAssertTrue(app.navigationBars["Favoritos"].waitForExistence(timeout: 5))
                capture("Favoritos con datos reales")
            }
            app.terminate()
        }
    }

    func testBundledCatalogAndPhotoOffline() {
        app.terminate()
        app.launchArguments = ["--ui-testing", "--catalog-bundle-sample", "--offline"]
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
        app.launchArguments = ["--ui-testing", "--catalog-bundle-sample", "--catalog-full-test", "--gallery"]
        app.launch()
        XCTAssertTrue(app.buttons["recent-planned-feature_7eb377470e968bbdb36536f6"].waitForExistence(timeout: 20))
        capture("08 Inicio")
        tap("dock-Mapa")
        XCTAssertTrue(app.buttons["map-start"].waitForExistence(timeout: 15))
        capture("09 Mapa")
        tap("dock-Inicio")
        tap("Abrir mapa para planear viaje")
        XCTAssertTrue(app.navigationBars["Desde dónde sales"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["trip-continue"].exists)
        capture("10 Origen inicial")
    }

    func testReferenceSelectorWithCatalog() {
        app.terminate()
        app.launchArguments = ["--ui-testing", "--catalog-bundle-sample", "--catalog-full-test", "--gallery", "--capture-catalog"]
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
        app.launchArguments = ["--ui-testing", "--catalog-bundle-sample", "--catalog-full-test", "--gallery"]
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
        app.launchArguments = ["--ui-testing", "--catalog-bundle-sample", "--gallery"]
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
        app.terminate()
        app.launchArguments = ["--ui-testing", "--catalog-bundle-sample", "--gallery", "--capture-catalog"]
        #if !LIVE_MAP_CAPTURE
        app.launchArguments.append("--catalog-full-test")
        #endif
        app.launch()
        tap("dock-Mapa")
        XCTAssertTrue(app.buttons["map-start"].waitForExistence(timeout: 15))
        capture("Mapa con catálogo real")
        tap("map-start")
        XCTAssertTrue(app.navigationBars["Desde dónde sales"].waitForExistence(timeout: 10))
        capture("Origen con catálogo real")
        tap("trip-search-toggle")
        let search = app.textFields["trip-place-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("Tijuana")
        if app.buttons["trip-place-0"].waitForExistence(timeout: 10) {
            capture("Buscar origen real")
        }
        tap("Cerrar")
        tap("trip-continue")
        XCTAssertTrue(app.navigationBars["A dónde vas"].waitForExistence(timeout: 10))
        capture("Destino con catálogo real")
        tap("Elegir destino en el mapa")
        XCTAssertTrue(app.navigationBars["Elegir destino"].waitForExistence(timeout: 5))
        capture("Selección de destino con catálogo real")
        tap("Cancelar")
        tap("trip-calculate")
        let result = app.staticTexts["trip-result"]
        guard result.waitForExistence(timeout: 28) else {
            throw XCTSkip("No se obtuvo un itinerario con rutas peatonales durante la captura.")
        }
        capture("Resultado con recorrido real")
        tap("trip-begin")
        XCTAssertTrue(app.buttons["trip-finish"].waitForExistence(timeout: 10))
        capture("Trayecto con recorrido real")
        let arrive = app.buttons["trip-walk-arrived"]
        if arrive.isHittable { arrive.tap() }
        if app.buttons["trip-board"].waitForExistence(timeout: 5) {
            capture("Espera para subir con recorrido real")
        }
    }

    func testWalkingLiveRoute() throws {
        app.terminate()
        app.launchArguments = ["--journey-fixture", "--ui-testing", "--walking-live-directions"]
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
