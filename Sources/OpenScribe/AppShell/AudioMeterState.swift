import Combine
import Foundation

@MainActor
final class AudioMeterState: ObservableObject {
    @Published var snapshot = AudioActivitySnapshot.silence
}
