import SwiftUI

struct SparklineView: View {
    let runs: [TaskRun]

    var body: some View {
        Canvas { context, size in
            let recent = runs
                .sorted { $0.startedAt < $1.startedAt }
                .suffix(20)

            guard recent.count > 1 else { return }

            let stepX = size.width / CGFloat(recent.count - 1)
            let midY = size.height / 2

            var path = Path()
            for (index, run) in recent.enumerated() {
                let x = CGFloat(index) * stepX
                let y: CGFloat = run.runStatus == .succeeded ? 2 : size.height - 2

                if index == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }

            // Draw the line
            context.stroke(path, with: .linearGradient(
                Gradient(colors: [.green, .red]),
                startPoint: CGPoint(x: 0, y: 0),
                endPoint: CGPoint(x: 0, y: size.height)
            ), lineWidth: 1.5)

            // Draw dots
            for (index, run) in recent.enumerated() {
                let x = CGFloat(index) * stepX
                let y: CGFloat = run.runStatus == .succeeded ? 2 : size.height - 2
                let color: Color = run.runStatus == .succeeded ? .green : .red
                let dot = Path(ellipseIn: CGRect(x: x - 2, y: y - 2, width: 4, height: 4))
                context.fill(dot, with: .color(color))
            }
        }
        .frame(width: 80, height: 24)
    }
}
