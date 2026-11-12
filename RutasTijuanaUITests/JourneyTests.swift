import XCTest

final class JourneyTests: XCTestCase {
    private let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launchArguments = ["--ui-testing", "--journey-fixture"]
        app.launch()
    }

    func testJourneyAndReset() {
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
        continueAfterFailure = true
        try audit("Inicio")
        tap("Elegir ubicación inicial")
        try audit("Origen")
        tap("stop-demo-1")
        tap("Continuar")
        XCTAssertFalse(app.buttons["Ver trayecto"].isEnabled)
        tap("stop-demo-4")
        try audit("Destino")
        tap("Ver trayecto")
        try audit("Resultado")
    }

    func testCatalogAndWalkingAccessibility() throws {
        app.terminate()
        app.launchArguments = ["--journey-fixture", "--ui-testing", "--catalog-info-sample", "--walking-fixture"]
        app.launch()
        tap("Explorar recorridos")
        let search = app.textFields["catalog-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        XCTAssertEqual(search.label, "Buscar nombre, grupo o información")
        XCTAssertGreaterThanOrEqual(search.frame.width, 44)
        search.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .withOffset(CGVector(dx: 0, dy: -20)).tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        search.typeText("\n")
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.keyboards.firstMatch)
        waitForExpectations(timeout: 5)
        tap("catalog-sample-route")
        tap("catalog-information")
        XCTAssertTrue(app.staticTexts["Descripción de ejemplo"].waitForExistence(timeout: 5))
        try audit("Información del catálogo", types: [.textClipped])
        tap("catalog-information-close")
        app.terminate()

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

    func testConsultationTextSizes() {
        let sizes = [
            "XS", "S", "M", "L", "XL", "XXL", "XXXL",
            "AccessibilityM", "AccessibilityL", "AccessibilityXL",
            "AccessibilityXXL", "AccessibilityXXXL",
        ]
        for size in sizes {
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
    }

    func testCatalogLineVisibility() {
        for dark in [false, true] {
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
    }

    func testCombinedTrip() {
        app.terminate()
        app.launchArguments = ["--ui-testing", "--trip-fixture"]
        app.launch()
        tap("trip-continue")
        tap("trip-calculate")
        XCTAssertTrue(app.staticTexts["trip-result"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts.matching(identifier: "trip-result").count, 1)
        for _ in 0..<8 {
            if app.buttons["trip-begin"].isHittable { break }
            app.scrollViews.firstMatch.swipeUp()
        }
        capture("Itinerario combinado")
        tap("trip-begin")
        capture("Caminata inicial del viaje")
        tap("trip-walk")
        tap("Iniciar guía")
        XCTAssertTrue(app.staticTexts["walking-instruction"].waitForExistence(timeout: 5))
        tap("walking-finish")
        app.buttons.matching(identifier: "Finalizar").allElementsBoundByIndex.last!.tap()
        tap("trip-walk-arrived")
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
        XCTAssertTrue(app.staticTexts["trip-result"].waitForExistence(timeout: 5))
    }

    func testTripManualSearch() {
        app.terminate()
        app.launchArguments = ["--ui-testing", "--trip-fixture"]
        app.launch()
        tap("trip-search-toggle")
        let search = app.textFields["trip-place-search"]
        for _ in 0..<8 {
            if search.isHittable { break }
            app.scrollViews.firstMatch.swipeUp()
        }
        search.tap()
        search.typeText("Parada 1\n")
        tap("trip-place-0")
        tap("trip-continue")
        tap("trip-calculate")
        XCTAssertTrue(app.staticTexts["trip-result"].waitForExistence(timeout: 10))
        capture("Consulta con origen manual")
    }

    func testNearbyStopSelectionKeepsSuggestions() {
        app.terminate()
        app.launchArguments = ["--ui-testing", "--trip-fixture"]
        app.launch()
        tap("trip-search-toggle")
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
        XCTAssertTrue(stop.waitForExistence(timeout: 5))
        XCTAssertTrue(stop.label.contains(description))
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
        tap("Iniciar guía")
        XCTAssertTrue(app.staticTexts["walking-instruction"].waitForExistence(timeout: 10))
        capture("Guía")
        tap("Ver pasos")
        XCTAssertTrue(app.navigationBars["Indicaciones"].waitForExistence(timeout: 5))
        tap("Cerrar")
        tap("Finalizar")
        app.buttons.matching(identifier: "Finalizar").allElementsBoundByIndex.last!.tap()
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
        tap("Paradas")
        XCTAssertFalse(app.buttons["catalog-sample-route"].exists)
        XCTAssertTrue(app.staticTexts["Sin coincidencias"].waitForExistence(timeout: 5))
        capture("Filtro de paradas")
    }

    func testSameStopIsRejected() {
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
        XCTAssertTrue(app.staticTexts["Horario y frecuencia: dato no disponible"].waitForExistence(timeout: 5))
        capture("Recorridos")
        let search = app.textFields["catalog-search"]
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
        XCTAssertTrue(app.staticTexts["06:00–20:00"].exists)
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

    func testBundledCatalogAndPhotoOffline() {
        app.terminate()
        app.launchArguments = ["--ui-testing", "--catalog-bundle-sample", "--offline"]
        for _ in 0..<2 {
            app.launch()
            tap("Explorar recorridos")
            tap("catalog-sample-route")
            tap("catalog-information")
            XCTAssertTrue(app.images["catalog-photo"].waitForExistence(timeout: 10))
            capture("Catálogo incluido sin conexión")
            app.terminate()
        }
    }

    #if LIVE_MAP_CAPTURE
    func testAppScreensWithCatalog() {
        app.terminate()
        app.launchArguments = ["--ui-testing", "--catalog-bundle-sample", "--capture-catalog"]
        app.launch()
        XCTAssertTrue(app.buttons["Explorar recorridos"].waitForExistence(timeout: 10))
        capture("Inicio")
        tap("Explorar recorridos")
        let route = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND identifier != %@ AND identifier != %@", "catalog-", "catalog-filter", "catalog-information")).firstMatch
        XCTAssertTrue(route.waitForExistence(timeout: 10))
        capture("Catálogo")
        route.tap()
        capture("Recorrido")
        app.navigationBars.buttons.firstMatch.tap()
        tap("Elegir ubicación inicial")
        XCTAssertTrue(app.navigationBars["Desde dónde sales"].waitForExistence(timeout: 10))
        let continueButton = app.buttons["trip-continue"]
        XCTAssertTrue(continueButton.isHittable)
        XCTAssertLessThanOrEqual(continueButton.frame.maxY, app.frame.maxY - 20)
        capture("Origen - puntos de prueba")
        tap("trip-continue")
        XCTAssertTrue(app.navigationBars["A dónde vas"].waitForExistence(timeout: 10))
        let calculateButton = app.buttons["trip-calculate"]
        XCTAssertTrue(calculateButton.isHittable)
        XCTAssertLessThanOrEqual(calculateButton.frame.maxY, app.frame.maxY - 20)
        capture("Destino - puntos de prueba")
        tap("trip-calculate")
        capture("Cálculo de viaje - puntos de prueba")
        let result = app.staticTexts["trip-result"]
        for _ in 0..<8 {
            if result.waitForExistence(timeout: 15) { break }
            let resume = app.buttons["trip-calculate"]
            if resume.label == "Continuar búsqueda", resume.isEnabled {
                for _ in 0..<8 where !resume.isHittable { app.scrollViews.firstMatch.swipeUp() }
                if resume.isHittable { resume.tap() }
            }
        }
        XCTAssertTrue(result.exists, "No se obtuvo un itinerario")
        if result.exists {
            for _ in 0..<8 where !result.isHittable || result.frame.minY > app.frame.height * 0.65 {
                app.scrollViews.firstMatch.swipeUp()
            }
            capture("Resultado de viaje - puntos de prueba")
            let begin = app.buttons["trip-begin"]
            for _ in 0..<8 where !begin.isHittable { app.scrollViews.firstMatch.swipeUp() }
            if begin.isHittable {
                begin.tap()
                if app.buttons["trip-finish"].waitForExistence(timeout: 10) {
                    capture("Etapa de viaje - puntos de prueba")
                }
            }
        }
    }

    func testWalkingLiveRoute() {
        app.terminate()
        app.launchArguments = ["--journey-fixture", "--ui-testing", "--walking-live-directions"]
        app.launch()
        tap("Elegir ubicación inicial")
        tap("stop-demo-1")
        tap("Continuar")
        tap("stop-demo-4")
        tap("Ver trayecto")
        tap("walking-start")
        XCTAssertTrue(app.buttons["Iniciar guía"].waitForExistence(timeout: 90))
        capture("Recorrido peatonal")
        tap("Iniciar guía")
        XCTAssertTrue(app.staticTexts["walking-instruction"].waitForExistence(timeout: 15))
        capture("Guía peatonal")
        tap("Ver pasos")
        XCTAssertTrue(app.navigationBars["Indicaciones"].waitForExistence(timeout: 5))
        capture("Indicaciones peatonales")
    }
    #endif

    private func tap(_ identifier: String) {
        let button = app.buttons[identifier]
        XCTAssertTrue(button.waitForExistence(timeout: 5), identifier)
        for _ in 0..<8 {
            if button.isHittable { break }
            app.scrollViews.firstMatch.swipeUp()
        }
        XCTAssertTrue(button.isHittable, identifier)
        button.tap()
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
