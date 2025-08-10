//
//  NgrokSetupView.swift
//  AICLICompanionHost
//
//  ngrok setup wizard and step views
//

import SwiftUI

// MARK: - ngrok Setup View
struct NgrokSetupView: View {
    @Binding var ngrokAuthToken: String
    @Binding var isPresented: Bool
    @Binding var needsRestart: Bool
    @State private var tempToken = ""
    @State private var currentStep = 1
    @State private var ngrokInstalled = false
    @State private var isInstalling = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "globe.badge.chevron.backward")
                    .font(.largeTitle)
                    .foregroundStyle(.blue)
                    .symbolRenderingMode(.hierarchical)

                VStack(alignment: .leading) {
                    Text("ngrok Setup Wizard")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text("Expose your server to the internet securely")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding()

            Divider()

            // Content
            VStack(spacing: 20) {
                // Step indicator
                HStack(spacing: 30) {
                    StepIndicator(number: 1, title: "Sign Up", isActive: currentStep >= 1)
                    StepIndicator(number: 2, title: "Get Token", isActive: currentStep >= 2)
                    StepIndicator(number: 3, title: "Configure", isActive: currentStep >= 3)
                }
                .padding(.vertical)

                // Step content
                Group {
                    switch currentStep {
                    case 1:
                        Step1View()
                    case 2:
                        Step2View(tempToken: $tempToken)
                    case 3:
                        Step3View(tempToken: tempToken, ngrokInstalled: ngrokInstalled)
                    default:
                        EmptyView()
                    }
                }
                .frame(minHeight: 200)

                Spacer()

                // Navigation buttons
                HStack {
                    if currentStep > 1 {
                        Button("Back") {
                            currentStep -= 1
                        }
                    }

                    Spacer()

                    Button("Cancel") {
                        isPresented = false
                    }
                    .buttonStyle(.plain)

                    if currentStep < 3 {
                        Button("Next") {
                            currentStep += 1
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(currentStep == 2 && tempToken.isEmpty)
                    } else {
                        Button("Finish") {
                            ngrokAuthToken = tempToken
                            needsRestart = true
                            isPresented = false
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(tempToken.isEmpty)
                    }
                }
            }
            .padding()
        }
        .frame(width: 500, height: 450)
        .onAppear {
            tempToken = ngrokAuthToken
            checkNgrokInstallation()
        }
    }

    private func checkNgrokInstallation() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        task.arguments = ["ngrok"]

        do {
            try task.run()
            task.waitUntilExit()
            ngrokInstalled = task.terminationStatus == 0
        } catch {
            ngrokInstalled = false
        }
    }
}

struct StepIndicator: View {
    let number: Int
    let title: String
    let isActive: Bool

    var body: some View {
        VStack(spacing: 4) {
            Circle()
                .fill(isActive ? Color.blue : Color.gray.opacity(0.3))
                .frame(width: 30, height: 30)
                .overlay(
                    Text("\(number)")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                )

            Text(title)
                .font(.caption)
                .foregroundStyle(isActive ? .primary : .secondary)
        }
    }
}

struct Step1View: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "person.crop.circle.badge.plus")
                .font(.system(size: 50))
                .foregroundStyle(.blue)
                .symbolRenderingMode(.hierarchical)

            Text("Create a free ngrok account")
                .font(.headline)

            Text("""
                ngrok provides secure tunnels to expose your local server to the internet. \
                Sign up for a free account to get started.
                """)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            Button("Open ngrok.com") {
                NSWorkspace.shared.open(URL(string: "https://ngrok.com/signup")!)
            }
            .buttonStyle(.bordered)
        }
        .padding()
    }
}

struct Step2View: View {
    @Binding var tempToken: String

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "key.fill")
                .font(.system(size: 50))
                .foregroundStyle(.blue)
                .symbolRenderingMode(.hierarchical)

            Text("Get your authentication token")
                .font(.headline)

            Text("After signing up, copy your auth token from the ngrok dashboard")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            Button("Open Dashboard") {
                NSWorkspace.shared.open(URL(string: "https://dashboard.ngrok.com/auth/your-authtoken")!)
            }
            .buttonStyle(.bordered)

            Divider()

            LabeledContent("Auth Token:") {
                SecureField("Paste your token here", text: $tempToken)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 250)
            }
        }
        .padding()
    }
}

struct Step3View: View {
    let tempToken: String
    let ngrokInstalled: Bool

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 50))
                .foregroundStyle(.green)
                .symbolRenderingMode(.hierarchical)

            Text("Ready to connect!")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Label(tempToken.isEmpty ? "Token required" : "Token configured",
                      systemImage: tempToken.isEmpty ? "xmark.circle" : "checkmark.circle")
                    .foregroundStyle(tempToken.isEmpty ? .red : .green)

                Label("Server will use bundled ngrok",
                      systemImage: "checkmark.circle")
                    .foregroundStyle(.green)

                Label("Authentication will be enforced",
                      systemImage: "lock.fill")
                    .foregroundStyle(.blue)
            }
            .font(.caption)

            Text("Click Finish to save settings. You'll need to restart the server for changes to take effect.")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}
