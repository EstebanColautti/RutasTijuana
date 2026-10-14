import XCTest

final class JourneyTests: XCTestCase {
    private let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
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
        XCTAssertFalse(app.buttons["Ver trayecto"].isEnabled)
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
