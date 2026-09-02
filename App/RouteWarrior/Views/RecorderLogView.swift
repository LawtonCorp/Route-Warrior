import SwiftUI

/// The field-test window into the recorder (D-019): every arm, start,
/// end, and permission change in plain words, newest first. Read this
/// before tuning `TripRecorder.Config`.
struct RecorderLogView: View {
    @Environment(RecordingPipeline.self) private var pipeline

    var body: some View {
        List {
            Section {
                if pipeline.log.isEmpty {
                    Text("Nothing yet — the log fills as drives are detected.")
                        .foregroundStyle(.secondary)
                }
                ForEach(pipeline.log.reversed()) { entry in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.text)
                            .font(.subheadline)
                        Text(entry.time, format: .dateTime.month(.abbreviated).day().hour().minute().second())
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            } footer: {
                Text("The last \(RecordingPipeline.logCapacity) recorder events, kept on this phone only.")
            }
        }
        .navigationTitle("Recorder log")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            Button("Clear") { pipeline.clearLog() }
                .disabled(pipeline.log.isEmpty)
        }
    }
}
