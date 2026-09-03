import SwiftUI

struct PlayerProgressSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let onEditingChanged: (Bool) -> Void
    @State private var isDragging = false
    @State private var localValue: Double = 0
    @State private var committedTarget: Double? = nil
    
    var body: some View {
        GeometryReader { geometry in
            let useLocal = isDragging || committedTarget != nil
            let percentage = (useLocal ? localValue : value - range.lowerBound) / (range.upperBound - range.lowerBound)
            let clampedPercentage = min(max(percentage, 0), 1)
            
            ZStack(alignment: .leading) {
                // Track
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.secondaryBackground)
                    .frame(height: 4)
                
                // Progress
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.accentColor)
                    .frame(width: geometry.size.width * clampedPercentage, height: 4)
                
                // Thumb
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: isDragging ? 24 : 20, height: isDragging ? 24 : 20)
                    .offset(x: geometry.size.width * clampedPercentage - (isDragging ? 12 : 10))
                    .animation(.easeInOut(duration: 0.1), value: isDragging)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        if !isDragging {
                            isDragging = true
                            localValue = value - range.lowerBound
                            onEditingChanged(true)
                        }

                        let percentage = max(0, min(1, gesture.location.x / geometry.size.width))
                        localValue = (range.upperBound - range.lowerBound) * percentage
                        // NOTE: Do not update external value while dragging
                    }
                    .onEnded { gesture in
                        // Commit the seek on release BEFORE ending drag state to avoid flicker
                        let percentage = max(0, min(1, gesture.location.x / geometry.size.width))
                        let committed = range.lowerBound + (range.upperBound - range.lowerBound) * percentage
                        // Display the committed position until external value catches up
                        localValue = committed - range.lowerBound
                        committedTarget = committed
                        // Update binding (triggers seek)
                        value = committed
                        // Notify end of editing
                        onEditingChanged(false)
                        // Now end drag state
                        isDragging = false
                    }
            )
            // Tap to seek can be implemented with a GestureDetector capturing location; removed here to avoid invalid signature
        }
        .frame(height: 44) // Larger touch target
        .onAppear { localValue = value - range.lowerBound }
        .onChange(of: value) { _, new in
            // Clear committed override once external value is in place
            if let target = committedTarget {
                if abs(new - target) <= max(0.15, 0.005 * (range.upperBound - range.lowerBound)) {
                    committedTarget = nil
                }
            }
        }
    }
}
