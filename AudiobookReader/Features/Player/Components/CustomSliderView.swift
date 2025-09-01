import SwiftUI

struct PlayerProgressSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let onEditingChanged: (Bool) -> Void
    @State private var isDragging = false
    @State private var localValue: Double = 0
    @State private var seekTimer: Timer?
    @State private var pendingSeekValue: Double?
    
    var body: some View {
        GeometryReader { geometry in
            let percentage = (isDragging ? localValue : value - range.lowerBound) / (range.upperBound - range.lowerBound)
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
                        let newValue = range.lowerBound + localValue
                        
                        // Store the pending value and set up debounced seeking
                        pendingSeekValue = newValue
                        scheduleSeek()
                    }
                    .onEnded { _ in
                        isDragging = false
                        
                        // Cancel any pending seek timer
                        seekTimer?.invalidate()
                        seekTimer = nil
                        
                        // Perform final seek if there's a pending value
                        if let pendingValue = pendingSeekValue {
                            value = pendingValue
                            pendingSeekValue = nil
                        }
                        
                        onEditingChanged(false)
                    }
            )
            // Tap to seek can be implemented with a GestureDetector capturing location; removed here to avoid invalid signature
        }
        .frame(height: 44) // Larger touch target
        .onAppear { localValue = value - range.lowerBound }
        .onDisappear {
            // Clean up timer when view disappears
            seekTimer?.invalidate()
            seekTimer = nil
        }
    }
    
    private func scheduleSeek() {
        // Cancel previous timer
        seekTimer?.invalidate()
        
        // Use shorter debounce for better responsiveness while still preventing excessive seeks
        seekTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: false) { _ in
            if let pendingValue = pendingSeekValue {
                value = pendingValue
                pendingSeekValue = nil
            }
        }
    }
}
