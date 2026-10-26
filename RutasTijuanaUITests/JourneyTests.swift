import XCTest

final class JourneyTests: XCTestCase {
    private let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        app.launchArguments = ["--ui-testing"]
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
        XCTAssertTrue(app.staticTexts["Sin coincidencias"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["catalog-sample-route"].exists)
    }

    func testSearchWithoutConnection() {
        app.terminate()
        app.launchArguments = ["--offline"]
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
        XCTAssertTrue(app.staticTexts["Sin coincidencias"].waitForExistence(timeout: 5))
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

    private func tap(_ identifier: String) {
        let button = app.buttons[identifier]
        XCTAssertTrue(button.waitForExistence(timeout: 5), identifier)
        for _ in 0..<5 {
            if button.isHittable { break }
            app.scrollViews.firstMatch.swipeUp()
        }
        button.tap()
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
