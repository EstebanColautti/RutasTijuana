import SwiftUI

struct CatalogPhoto: View {
    let id: String
    @ObservedObject private var repository = CatalogRepository.shared
    var body: some View {
        if let url = repository.imageURL(for: id), let image = UIImage(contentsOfFile: url.path) {
            Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 240)
                .accessibilityLabel("Fotografía del transporte")
                .accessibilityIdentifier("catalog-photo")
        } else {
            Label("Fotografía no disponible", systemImage: "photo")
        }
    }
}
