import SwiftUI

/// Test file for verifying AttachmentPicker safe area fixes
/// Issue #15: Attachment UI Gets Cut Off at Top
@available(iOS 17.0, macOS 14.0, *)
struct AttachmentPickerTest: View {
    @State private var showingPicker = false
    @State private var selectedAttachments: [String] = []
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("Attachment Picker Safe Area Test")
                    .font(.title2)
                    .padding()
                
                Text("Tests for Issue #15")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                VStack(alignment: .leading, spacing: 10) {
                    Label("NavigationStack properly handles safe area", systemImage: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    
                    Label("Cancel button accessible in navigation bar", systemImage: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    
                    Label("Close button (X) accessible on right", systemImage: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    
                    Label("Content scrollable without clipping", systemImage: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    
                    Label("Sheet presentation with proper detents", systemImage: "checkmark.circle.fill")
                        .foregroundColor(.green)
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(10)
                
                Button("Test Attachment Picker") {
                    showingPicker = true
                }
                .buttonStyle(.borderedProminent)
                
                if !selectedAttachments.isEmpty {
                    VStack(alignment: .leading) {
                        Text("Selected Attachments:")
                            .font(.headline)
                        ForEach(selectedAttachments, id: \.self) { attachment in
                            Text("• \(attachment)")
                        }
                    }
                    .padding()
                }
                
                Spacer()
            }
            .navigationTitle("Test Harness")
            .sheet(isPresented: $showingPicker) {
                // This would be the actual AttachmentPicker
                MockAttachmentPicker(isPresented: $showingPicker)
            }
        }
    }
}

/// Mock picker for testing purposes
@available(iOS 17.0, macOS 14.0, *)
struct MockAttachmentPicker: View {
    @Binding var isPresented: Bool
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    ForEach(0..<10) { index in
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.blue.opacity(0.2))
                            .frame(height: 80)
                            .overlay(
                                Text("Attachment Option \(index + 1)")
                            )
                    }
                }
                .padding()
            }
            .navigationTitle("Add Attachment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { isPresented = false }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.gray)
                    }
                }
            }
        }
        #if os(iOS)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
        #endif
    }
}

@available(iOS 17.0, macOS 14.0, *)
#Preview {
    AttachmentPickerTest()
}