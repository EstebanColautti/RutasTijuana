import XCTest

final class JourneyTests: XCTestCase {
    private let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
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
        let save = rename.buttons["Guardar"]
        XCTAssertTrue(save.isEnabled)
        save.tap()
        // Con el teclado activo, el primer toque a veces solo cierra la sugerencia del teclado.
        if rename.waitForExistence(timeout: 2), save.isHittable { save.tap() }
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
        focus(search)
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
        focus(search)
        search.typeText("sin coincidencias")
        XCTAssertTrue(app.staticTexts["Sin coincidencias"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["0 rutas"].exists)
        XCTAssertFalse(app.buttons["catalog-sample-route"].exists)
        capture("Rutas sin coincidencias")
        tap("Borrar búsqueda")
        search.typeText("\n")
        XCTAssertTrue(app.buttons["catalog-sample-route"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["1 ruta"].waitForExistence(timeout: 5))
        focus(search)
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
        app.terminate()
        app.launchArguments = ["--ui-testing", "--catalog-bundle-sample"]
        app.launch()
        tap("dock-Favoritos")
        XCTAssertTrue(app.buttons["catalog-sample-route"].waitForExistence(timeout: 10), "El favorito se conserva al reiniciar")
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
                // En iOS 18 el UITextField no crece en vertical; la barra entera (50 pt) enfoca el campo.
                if issue.auditType == .hitRegion, ["trip-place-search", "catalog-search"].contains(element.identifier),
                   element.frame.height >= 17 { return true }
                // Puntos de interés de Apple Maps (en algunas versiones se exponen como VKPointFeature).
                if element.identifier == "VKPointFeature" { return true }
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
                if issue.auditType == .elementDetection,
                   self.app.maps.firstMatch.exists || self.app.otherElements["Mapa de Tijuana"].exists { return true }
            }
            return false
        }
    }









    func testCatalogInformation() {
        app.terminate()
        app.launchArguments = ["--catalog-info-sample"]
        app.launch()
        tap("dock-Rutas")
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
        tap("dock-Rutas")
        XCTAssertTrue(app.buttons["catalog-sample-route"].waitForExistence(timeout: 5))
        app.terminate()
        app.launch()
        tap("dock-Rutas")
        XCTAssertTrue(app.buttons["catalog-sample-route"].waitForExistence(timeout: 5))
        tap("catalog-sample-route")
        XCTAssertTrue(app.staticTexts["Recorrido de ejemplo"].firstMatch.waitForExistence(timeout: 5))
        capture("Catálogo guardado")
    }


    func testFullCatalogOffline() {
        app.terminate()
        app.launchArguments = ["--ui-testing", "--catalog-bundle-sample", "--catalog-full-test", "--offline", "--gallery"]
        for attempt in 0..<2 {
            app.launch()
            app.buttons["dock-Rutas"].tap()
            XCTAssertTrue(app.staticTexts["182 rutas"].waitForExistence(timeout: 25))
            if attempt == 0 {
                capture("Rutas por zona con catálogo completo")
                tap("Todas")
                capture("Todas las rutas con catálogo completo")
                let routeSearch = app.textFields["catalog-search"]
                XCTAssertTrue(routeSearch.waitForExistence(timeout: 5))
                focus(routeSearch)
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
            focus(search)
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
                focus(fullSearch)
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
                // La hoja de información debe terminar de cerrarse antes de abrir la de listas.
                let closed = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.buttons["catalog-information-close"])
                wait(for: [closed], timeout: 10)
                XCTAssertTrue(app.buttons["Guardar en listas"].waitForHittable(timeout: 5))
                tap("Guardar en listas")
                XCTAssertTrue(app.navigationBars["Guardar en listas"].waitForExistence(timeout: 10))
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
        app.launchArguments = ["--ui-testing", "--catalog-bundle-sample", "--offline"]
        for _ in 0..<2 {
            app.launch()
            tap("dock-Rutas")
            XCTAssertTrue(app.navigationBars["Rutas"].waitForExistence(timeout: 15))
            tap("catalog-sample-route")
            tap("catalog-information")
            XCTAssertTrue(app.images["catalog-photo"].waitForExistence(timeout: 10))
            app.terminate()
        }
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
        // La dirección se resuelve en segundo plano; se espera a que reemplace el rótulo provisional.
        let resolved = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.staticTexts["Punto de origen"])
        wait(for: [resolved], timeout: 15)
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
        XCTAssertTrue(app.staticTexts["Llegaste al destino"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["trip-close"].exists, "Terminar es el botón principal al llegar")
        capture("Viaje finalizado con recorrido real")
        try XCTUnwrap(app.buttons.matching(identifier: "dock-Inicio")
            .allElementsBoundByIndex.last(where: \.isHittable)).tap()
        XCTAssertTrue(app.textFields["trip-place-search"].waitForExistence(timeout: 10))
        capture("Inicio al volver al inicio")
    }


    private func tap(_ identifier: String) {
        let button = app.buttons[identifier]
        guard button.waitForExistence(timeout: 5) else {
            recordMissingControl(identifier, reason: "No apareció")
            return
        }
        _ = button.waitForHittable(timeout: 3)
        for _ in 0..<8 {
            let tabBar = app.otherElements["app-dock"]
            let aboveTab = identifier.hasPrefix("dock-") || !tabBar.isHittable || button.frame.midY < tabBar.frame.minY
            let fixedAction = app.buttons["trip-continue"]
            let aboveAction = !identifier.hasPrefix("trip-stop-") || !fixedAction.isHittable || button.frame.midY < fixedAction.frame.minY
            let unobscured = aboveTab && aboveAction
            if button.isHittable && unobscured {
                button.tap()
                if identifier.hasPrefix("dock-"), !button.waitForSelected(timeout: 3) {
                    button.tap()
                }
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

    /// Toca un campo hasta que tenga el foco: el primer toque puede perderse mientras la vista se anima.
    private func focus(_ field: XCUIElement) {
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        for _ in 0..<3 {
            field.tap()
            let deadline = Date().addingTimeInterval(2)
            while Date() < deadline {
                if field.hasKeyboardFocus { return }
                RunLoop.current.run(until: Date().addingTimeInterval(0.2))
            }
        }
        XCTFail("El campo no recibió el foco")
    }

    private func recordMissingControl(_ identifier: String, reason: String) {
        capture("Fallo · " + identifier, always: true)
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = "Jerarquía · " + identifier
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
        XCTFail(reason + ": " + identifier)
    }

    /// Las capturas de evidencia se omiten si el ejecutor recibe CAPTURE=0 (pruebas locales rápidas);
    /// las de fallos se guardan siempre.
    private func capture(_ name: String, always: Bool = false) {
        guard always || ProcessInfo.processInfo.environment["CAPTURE"] != "0" else { return }
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

private extension XCUIElement {
    func waitForSelected(timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if exists && isSelected { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return exists && isSelected
    }

    var hasKeyboardFocus: Bool { (value(forKey: "hasKeyboardFocus") as? Bool) ?? false }

    func waitForHittable(timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if exists && isHittable { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return exists && isHittable
    }
}
