import SwiftUI

@available(iOS 16.0, macOS 13.0, *)
struct ChatLoadingView: View {
    let progressInfo: ProgressInfo?
    let colorScheme: ColorScheme
    
    @State private var dotOpacity: [Double] = [1.0, 0.3, 0.3]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Main loading indicator
            HStack(spacing: 16) {
                // Animated dots
                HStack(spacing: 4) {
                    ForEach(0..<3) { index in
                        Circle()
                            .fill(Colors.accentWarning)
                            .frame(width: 8, height: 8)
                            .opacity(dotOpacity[index])
                    }
                }
                .onAppear {
                    animateDots()
                }
                
                Text("Thinking")
                    .font(Typography.font(.body))
                    .foregroundColor(Colors.textSecondary(for: colorScheme))
                
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Colors.bgCard(for: colorScheme))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Colors.strokeLight, lineWidth: 1)
                    )
            )
            
            // Progress info if available
            if let progress = progressInfo {
                VStack(alignment: .leading, spacing: 4) {
                    Text(progress.stage)
                        .font(Typography.font(.caption))
                        .fontWeight(.medium)
                        .foregroundColor(Colors.textPrimary(for: colorScheme))
                    
                    Text(progress.message)
                        .font(Typography.font(.caption))
                        .foregroundColor(Colors.textSecondary(for: colorScheme))
                    
                    if let progressValue = progress.progress {
                        ProgressView(value: progressValue)
                            .tint(Colors.accentWarning)
                            .padding(.top, 4)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Colors.bgCard(for: colorScheme).opacity(0.8))
                )
            }
        }
        .frame(maxWidth: 400, alignment: .leading)
    }
    
    private func animateDots() {
        withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: false)) {
            dotOpacity = [0.3, 1.0, 0.3]
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: false)) {
                dotOpacity = [0.3, 0.3, 1.0]
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: false)) {
                dotOpacity = [1.0, 0.3, 0.3]
            }
        }
    }
}