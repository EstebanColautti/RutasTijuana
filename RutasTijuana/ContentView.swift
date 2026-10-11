import SwiftUI

struct ContentView: View {
    @State private var estado = "Pendiente"

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "bus.fill")
                .font(.system(size: 40))
                .foregroundColor(.blue)

            Text("Rutas Tijuana")
                .font(.title2)
                .fontWeight(.bold)

            Text("Consulta de horarios y frecuencias del transporte público")

            Text("Estado: \(estado)")

            Button("Consultar horarios") {
                estado = "Consulta registrada"
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
