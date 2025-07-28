import SwiftUI

/// Divider with "or" text in the middle
@available(iOS 14.0, macOS 11.0, *)
public struct DividerView: View {
    let text: String
    
    public init(text: String = "or") {
        self.text = text
    }
    
    public var body: some View {
        HStack(spacing: Spacing.md) {
            // Left line
            Rectangle()
                .fill(Colors.surface10)
                .frame(height: 1)
            
            // Text
            Text(text)
                .font(Typography.font(.caption))
                .foregroundColor(Colors.ink700.opacity(0.6))
            
            // Right line
            Rectangle()
                .fill(Colors.surface10)
                .frame(height: 1)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Preview
@available(iOS 14.0, macOS 11.0, *)
struct DividerView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 40) {
            DividerView()
            DividerView(text: "OR")
        }
        .padding()
    }
}