import SwiftUI
import DateGuessCore

/// The cameras that took undated photos, and the years the user remembers using each one.
struct CamerasView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        let cameras = state.undatedCameras
        if cameras.isEmpty {
            ContentUnavailableView {
                Label("No camera details found", systemImage: "camera")
            } description: {
                Text(state.settings.scan.deepCheck
                     ? "None of your undated photos say which camera took them. Scanned prints never do."
                     : "Turn on “Photos whose file has no capture date” under Find Undated Photos ▸ Options and scan again to read camera details.")
            }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("If you remember when you had a camera, enter the years. Every undated photo it took is dated within them.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                    ForEach(cameras, id: \.name) { camera in
                        CameraRow(name: camera.name, count: camera.count)
                        Divider().padding(.leading, 56)
                    }
                }
                .padding(.bottom, 40)
            }
        }
    }
}

struct CameraRow: View {
    @Environment(AppState.self) private var state
    var name: String
    var count: Int

    private var period: CameraPeriod? { state.cameraPeriods.first { $0.id == name } }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "camera.fill")
                .font(.title3)
                .foregroundStyle(Theme.accent)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.body.weight(.medium))
                Text("\(count.formatted()) undated photo\(count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(minWidth: 160, maxWidth: .infinity, alignment: .leading)
            Text("Used from").foregroundStyle(.secondary)
            NumberField(title: "year", value: Binding(
                get: { period?.fromYear },
                set: { state.setCameraYears(name, from: $0, to: period?.toYear) }),
                range: YearBounds.earliestPhotoYear...YearBounds.currentYear(), width: 64)
            Text("to").foregroundStyle(.secondary)
            NumberField(title: "year", value: Binding(
                get: { period?.toYear },
                set: { state.setCameraYears(name, from: period?.fromYear, to: $0) }),
                range: YearBounds.earliestPhotoYear...YearBounds.currentYear(), width: 64)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }
}
