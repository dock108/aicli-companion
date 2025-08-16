//
//  ActivityMonitorCharts.swift
//  AICLICompanionHost
//
//  Chart components for the Activity Monitor
//

import SwiftUI
import Charts

// MARK: - Performance Chart
struct PerformanceChart: View {
    let title: String
    let data: [Double]
    let color: Color
    let unit: String

    init() {
        self.title = "Performance Metrics"
        self.data = []
        self.color = .blue
        self.unit = "Value"
    }

    init(title: String, data: [Double], color: Color, unit: String) {
        self.title = title
        self.data = data
        self.color = color
        self.unit = unit
    }

    var body: some View {
        GroupBox(title) {
            if data.isEmpty {
                ContentUnavailableView(
                    "No Data",
                    systemImage: "chart.line.uptrend.xyaxis",
                    description: Text("Performance data will appear here")
                )
                .frame(height: 200)
            } else {
                Chart(Array(data.enumerated()), id: \.offset) { index, value in
                    LineMark(
                        x: .value("Time", index),
                        y: .value(unit, value)
                    )
                    .foregroundStyle(color)

                    AreaMark(
                        x: .value("Time", index),
                        y: .value(unit, value)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [color.opacity(0.3), color.opacity(0.1)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .chartXAxis(.hidden)
                .frame(height: 200)
            }
        }
    }
}

// MARK: - Memory Usage Chart
struct MemoryUsageChart: View {
    @State private var memoryData: [Double] = []
    @State private var timer: Timer?

    var body: some View {
        PerformanceChart(
            title: "Memory Usage",
            data: memoryData,
            color: .blue,
            unit: "MB"
        )
        .onAppear {
            startMonitoring()
        }
        .onDisappear {
            stopMonitoring()
        }
    }

    private func startMonitoring() {
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            let memoryUsage = getCurrentMemoryUsage()

            DispatchQueue.main.async {
                memoryData.append(memoryUsage)
                if memoryData.count > 50 {
                    memoryData.removeFirst()
                }
            }
        }
    }

    private func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    private func getCurrentMemoryUsage() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)/4

        let result: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }

        if result == KERN_SUCCESS {
            return Double(info.resident_size) / 1024.0 / 1024.0 // Convert to MB
        }

        return 0.0
    }
}

// MARK: - CPU Usage Chart
struct CPUUsageChart: View {
    @State private var cpuData: [Double] = []
    @State private var timer: Timer?

    var body: some View {
        PerformanceChart(
            title: "CPU Usage",
            data: cpuData,
            color: .green,
            unit: "%"
        )
        .onAppear {
            startMonitoring()
        }
        .onDisappear {
            stopMonitoring()
        }
    }

    private func startMonitoring() {
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            let cpuUsage = getCurrentCPUUsage()

            DispatchQueue.main.async {
                cpuData.append(cpuUsage)
                if cpuData.count > 50 {
                    cpuData.removeFirst()
                }
            }
        }
    }

    private func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    private func getCurrentCPUUsage() -> Double {
        // Simplified CPU monitoring - return a placeholder value
        // In a real implementation, you'd use system APIs to get actual CPU usage
        return Double.random(in: 5...25) // Simulate CPU usage between 5-25%
    }
}
