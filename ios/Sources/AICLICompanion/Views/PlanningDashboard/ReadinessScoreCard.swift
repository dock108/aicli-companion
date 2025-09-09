//
//  ReadinessScoreCard.swift
//  AICLICompanion
//
//  Visual component for displaying readiness score
//

import SwiftUI

struct ReadinessScoreCard: View {
    let score: Int
    let level: InternalReadinessLevel
    @State private var animatedScore: Double = 0
    
    var scoreColor: Color {
        switch score {
        case 90...100: return .green
        case 75...89: return .yellow
        case 60...74: return .orange
        default: return .red
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            // Header
            HStack {
                Text("Project Readiness")
                    .font(.headline)
                Spacer()
                Text("\(score)%")
                    .font(.title2)
                    .bold()
                    .foregroundColor(scoreColor)
            }
            
            // Progress Bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.2))
                        .frame(height: 20)
                        .cornerRadius(10)
                    
                    Rectangle()
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [scoreColor.opacity(0.8), scoreColor]),
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geometry.size.width * CGFloat(animatedScore) / 100, height: 20)
                        .cornerRadius(10)
                        .animation(.easeOut(duration: 1), value: animatedScore)
                }
            }
            .frame(height: 20)
            
            // Status
            HStack(spacing: Spacing.sm) {
                Text(level.icon)
                    .font(.title3)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(level.label)
                        .font(.subheadline)
                        .bold()
                        .foregroundColor(level.color)
                    
                    Text(level.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, Spacing.sm)
        }
        .padding()
        .background(scoreColor.opacity(0.1))
        .cornerRadius(12)
        .onAppear {
            withAnimation(.easeOut(duration: 1)) {
                animatedScore = Double(score)
            }
        }
        .onChange(of: score) { newValue in
            withAnimation(.easeOut(duration: 0.5)) {
                animatedScore = Double(newValue)
            }
        }
    }
}

// Compact version for smaller spaces
struct CompactReadinessCard: View {
    let score: Int
    let level: InternalReadinessLevel
    
    var scoreColor: Color {
        switch score {
        case 90...100: return .green
        case 75...89: return .yellow
        case 60...74: return .orange
        default: return .red
        }
    }
    
    var body: some View {
        HStack {
            // Circular progress
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 6)
                
                Circle()
                    .trim(from: 0, to: CGFloat(score) / 100)
                    .stroke(scoreColor, lineWidth: 6)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut, value: score)
            }
            .frame(width: 50, height: 50)
            .overlay(
                Text("\(score)%")
                    .font(.caption)
                    .bold()
            )
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(level.icon)
                        .font(.caption)
                    Text(level.label)
                        .font(.caption)
                        .bold()
                }
                
                Text(level.description)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background(scoreColor.opacity(0.1))
        .cornerRadius(8)
    }
}

// Preview
struct ReadinessScoreCard_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            ReadinessScoreCard(score: 85, level: .partial)
            CompactReadinessCard(score: 65, level: .incomplete)
        }
        .padding()
    }
}
