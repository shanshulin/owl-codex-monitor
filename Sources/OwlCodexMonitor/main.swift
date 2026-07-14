import AppKit

if CommandLine.arguments.contains("--self-test") {
    let half = QuotaUsage(period: "本月", used: 45, limit: 90)
    precondition(half.fraction == 0.5)
    precondition(QuotaUsage(period: "本月", used: 120, limit: 90).fraction == 1)

    let windowStart = ISO8601DateFormatter().string(from: Date())
    let json = """
    {"id":1,"status":"active","expires_at":null,"effective_daily_limit_usd":23,"daily_usage_usd":2.44,"weekly_usage_usd":2.44,"monthly_usage_usd":2.44,"daily_window_start":"\(windowStart)","daily_rollover_amount_usd":7,"daily_rollover_remaining_usd":5,"daily_rollover_window_start":"\(windowStart)","group":{"name":"Plan","daily_limit_usd":30,"weekly_limit_usd":113,"monthly_limit_usd":450,"daily_limit_rollover_enabled":true}}
    """
    let subscription = try JSONDecoder().decode(Subscription.self, from: Data(json.utf8))
    precondition(subscription.primaryQuota == QuotaUsage(period: "本月", used: 2.44, limit: 450))
    precondition(abs((subscription.dailyQuota?.used ?? 0) - 4.44) < 0.0001)
    precondition(abs((subscription.dailyQuota?.limit ?? 0) - 30) < 0.0001)
    precondition(subscription.weeklyQuota == QuotaUsage(period: "本周", used: 2.44, limit: 113))
    precondition(subscription.monthlyQuota == QuotaUsage(period: "本月", used: 2.44, limit: 450))
    precondition(subscription.activeRollover == RolloverUsage(amount: 7, remaining: 5))

    let noDailyLimitJSON = """
    {"id":2,"status":"active","expires_at":null,"effective_daily_limit_usd":23,"daily_usage_usd":2.44,"daily_rollover_amount_usd":7,"daily_rollover_remaining_usd":5,"weekly_usage_usd":2.44,"monthly_usage_usd":2.44,"no_daily_limit_effective":true,"group":{"name":"Plan","daily_limit_usd":30,"weekly_limit_usd":113,"monthly_limit_usd":450,"daily_limit_rollover_enabled":true}}
    """
    let noDailyLimitSubscription = try JSONDecoder().decode(Subscription.self, from: Data(noDailyLimitJSON.utf8))
    precondition(noDailyLimitSubscription.dailyQuota == nil)
    precondition(noDailyLimitSubscription.activeRollover == nil)
    precondition(noDailyLimitSubscription.weeklyQuota == QuotaUsage(period: "本周", used: 2.44, limit: 113))
    precondition(noDailyLimitSubscription.monthlyQuota == QuotaUsage(period: "本月", used: 2.44, limit: 450))
    print("Self-test passed")
    exit(0)
}

if CommandLine.arguments.contains("--snapshot-test") {
    Task {
        do {
            let snapshot = try await OwlAPIClient.shared.fetchSnapshot()
            let daily = snapshot.activeSubscription?.dailyQuota
            let weekly = snapshot.activeSubscription?.weeklyQuota
            let monthly = snapshot.activeSubscription?.monthlyQuota
            let rollover = snapshot.activeSubscription?.activeRollover
            print(String(
                format: "daily=%.2f/%.2f weekly=%.2f/%.2f monthly=%.2f/%.2f rollover=%.2f/%.2f",
                daily?.used ?? 0,
                daily?.limit ?? 0,
                weekly?.used ?? 0,
                weekly?.limit ?? 0,
                monthly?.used ?? 0,
                monthly?.limit ?? 0,
                rollover?.remaining ?? 0,
                rollover?.amount ?? 0
            ))
            exit(0)
        } catch {
            print("snapshot_error=\(error.localizedDescription)")
            exit(4)
        }
    }
    RunLoop.main.run()
}

if let previewIndex = CommandLine.arguments.firstIndex(of: "--render-menubar-preview"),
   CommandLine.arguments.indices.contains(previewIndex + 1) {
    _ = NSApplication.shared
    let outputURL = URL(fileURLWithPath: CommandLine.arguments[previewIndex + 1])
    let canvas = NSImage(size: NSSize(width: 100, height: 28))
    canvas.lockFocus()
    NSColor(calibratedWhite: 0.05, alpha: 1).setFill()
    NSBezierPath(rect: NSRect(x: 0, y: 0, width: 100, height: 28)).fill()
    let rings = MenuBarRingImage.make(dailyFraction: 0.42, weeklyFraction: 0.55, monthlyFraction: 0.68)
    rings.isTemplate = false
    rings.draw(in: NSRect(x: 22, y: 6, width: 56, height: 16))
    canvas.unlockFocus()

    guard let tiff = canvas.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else { exit(3) }
    try png.write(to: outputURL)
    print(outputURL.path)
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
