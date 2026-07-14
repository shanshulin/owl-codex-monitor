import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let api = OwlAPIClient.shared
    private var statusItem: NSStatusItem!
    private var loginWindow: LoginWindowController?
    private var refreshTimer: Timer?
    private var isLoggedIn = false
    private var sessionGeneration = 0
    private var planMenuItem: NSMenuItem!
    private var dailyMenuItem: NSMenuItem!
    private var rolloverMenuItem: NSMenuItem!
    private var weeklyMenuItem: NSMenuItem!
    private var monthlyMenuItem: NSMenuItem!
    private var statsMenuItem: NSMenuItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureMenuBar()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }

        Task {
            isLoggedIn = await api.hasStoredLogin()
            if isLoggedIn {
                refresh()
            } else {
                updateMenuBar(error: OwlAPIError.loginExpired, loggedIn: false)
                showLogin()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        refreshTimer?.invalidate()
    }

    private func configureMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: 68)
        statusItem.button?.imageScaling = .scaleNone
        updateStatusButton(dailyFraction: 0, weeklyFraction: 0, monthlyFraction: 0)

        let menu = NSMenu()
        let header = NSMenuItem(title: "Owl AI 用量", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        planMenuItem = NSMenuItem(title: "套餐：等待登录", action: nil, keyEquivalent: "")
        dailyMenuItem = NSMenuItem(title: "今日：--", action: nil, keyEquivalent: "")
        rolloverMenuItem = NSMenuItem(title: "昨日结余：--", action: nil, keyEquivalent: "")
        weeklyMenuItem = NSMenuItem(title: "本周：--", action: nil, keyEquivalent: "")
        monthlyMenuItem = NSMenuItem(title: "本月：--", action: nil, keyEquivalent: "")
        statsMenuItem = NSMenuItem(title: "历史：--", action: nil, keyEquivalent: "")
        rolloverMenuItem.isHidden = true
        for item in [planMenuItem!, dailyMenuItem!, rolloverMenuItem!, weeklyMenuItem!, monthlyMenuItem!, statsMenuItem!] {
            item.isEnabled = false
            menu.addItem(item)
        }

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "刷新", action: #selector(menuRefresh), keyEquivalent: "r"))
        menu.addItem(NSMenuItem(title: "登录 / 更换账号", action: #selector(menuLogin), keyEquivalent: "l"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出登录", action: #selector(logout), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "退出", action: #selector(quit), keyEquivalent: "q"))
        for item in menu.items { item.target = self }
        statusItem.menu = menu
    }

    private func refresh() {
        guard isLoggedIn else {
            updateMenuBar(error: OwlAPIError.loginExpired, loggedIn: false)
            return
        }
        let sessionGeneration = sessionGeneration
        statusItem.button?.toolTip = "正在刷新 Owl AI 用量"
        Task {
            do {
                let snapshot = try await api.fetchSnapshot()
                guard sessionGeneration == self.sessionGeneration else { return }
                updateMenuBar(snapshot: snapshot)
            } catch {
                guard sessionGeneration == self.sessionGeneration else { return }
                if case OwlAPIError.loginExpired = error {
                    isLoggedIn = false
                    updateMenuBar(error: error, loggedIn: false)
                    showLogin()
                    return
                }
                updateMenuBar(error: error, loggedIn: isLoggedIn)
            }
        }
    }

    private func showLogin() {
        if loginWindow == nil {
            loginWindow = LoginWindowController(savedEmail: KeychainStore.read(account: "email"))
            loginWindow?.onLogin = { [weak self] email, password in
                guard let self else { return }
                self.sessionGeneration += 1
                let sessionGeneration = self.sessionGeneration
                Task {
                    do {
                        try await self.api.login(email: email, password: password)
                        guard sessionGeneration == self.sessionGeneration else { return }
                        self.isLoggedIn = true
                        self.loginWindow?.finishLogin()
                        self.refresh()
                    } catch {
                        guard sessionGeneration == self.sessionGeneration else { return }
                        self.loginWindow?.showError(error.localizedDescription)
                    }
                }
            }
        }
        NSApp.activate(ignoringOtherApps: true)
        loginWindow?.showWindow(nil)
        loginWindow?.window?.makeKeyAndOrderFront(nil)
    }

    @objc private func menuRefresh() { refresh() }
    @objc private func menuLogin() { showLogin() }
    @objc private func logout() {
        sessionGeneration += 1
        isLoggedIn = false
        updateMenuBar(error: OwlAPIError.loginExpired, loggedIn: false)
        showLogin()
        Task {
            await api.logout()
        }
    }
    @objc private func quit() { NSApp.terminate(nil) }

    private func updateMenuBar(snapshot: MonitorSnapshot) {
        let hasDailyLimit = snapshot.activeSubscription.map { $0.dailyQuota != nil } ?? true
        if let subscription = snapshot.activeSubscription {
            let daily = subscription.dailyQuota
            let weekly = subscription.weeklyQuota
            let monthly = subscription.monthlyQuota
            let rollover = subscription.activeRollover
            updateStatusButton(
                dailyFraction: daily?.fraction,
                weeklyFraction: weekly?.fraction ?? 0,
                monthlyFraction: monthly?.fraction ?? 0
            )
            planMenuItem.title = "套餐：\(subscription.group?.name ?? "有效订阅")"
            dailyMenuItem.isHidden = daily == nil
            if let daily {
                dailyMenuItem.title = quotaMenuTitle(label: rollover == nil ? "今日" : "今日（含结余）", quota: daily)
            }
            weeklyMenuItem.title = quotaMenuTitle(label: "本周", quota: weekly)
            monthlyMenuItem.title = quotaMenuTitle(label: "本月", quota: monthly)
            if daily != nil, let rollover {
                rolloverMenuItem.title = String(
                    format: "昨日结余：总额 $%.2f · 已用 $%.2f · 剩余 $%.2f",
                    rollover.amount,
                    rollover.used,
                    rollover.remaining
                )
                rolloverMenuItem.isHidden = false
            } else {
                rolloverMenuItem.isHidden = true
            }
        } else {
            updateStatusButton(dailyFraction: 0, weeklyFraction: 0, monthlyFraction: 0)
            planMenuItem.title = "套餐：当前无有效订阅"
            dailyMenuItem.title = "今日：--"
            rolloverMenuItem.isHidden = true
            weeklyMenuItem.title = "本周：--"
            monthlyMenuItem.title = "本月：--"
        }
        statsMenuItem.title = String(
            format: "历史：%@ 次请求 · $%.2f",
            snapshot.stats.totalRequests.formatted(),
            snapshot.stats.totalActualCost
        )
        if !hasDailyLimit {
            statusItem.button?.toolTip = "左：周额度 · 右：月额度\n\(weeklyMenuItem.title)\n\(monthlyMenuItem.title)"
        } else {
            statusItem.button?.toolTip = "左：日额度 · 中：周额度 · 右：月额度\n\(dailyMenuItem.title)\n\(weeklyMenuItem.title)\n\(monthlyMenuItem.title)"
        }
    }

    private func updateMenuBar(error: Error, loggedIn: Bool) {
        updateStatusButton(dailyFraction: 0, weeklyFraction: 0, monthlyFraction: 0)
        planMenuItem.title = loggedIn ? "套餐：刷新失败" : "套餐：请登录 Owl AI"
        dailyMenuItem.title = "今日：--"
        rolloverMenuItem.isHidden = true
        weeklyMenuItem.title = "本周：--"
        monthlyMenuItem.title = "本月：--"
        statsMenuItem.title = "状态：\(error.localizedDescription)"
        statusItem.button?.toolTip = error.localizedDescription
    }

    private func quotaMenuTitle(label: String, quota: QuotaUsage?) -> String {
        guard let quota else { return "\(label)：未设置额度" }
        return String(
            format: "%@：$%.2f / $%.2f · 剩余 $%.2f",
            label,
            quota.used,
            quota.limit,
            max(quota.limit - quota.used, 0)
        )
    }

    private func updateStatusButton(dailyFraction: Double?, weeklyFraction: Double, monthlyFraction: Double) {
        statusItem.length = dailyFraction == nil ? 48 : 68
        statusItem.button?.image = MenuBarRingImage.make(
            dailyFraction: dailyFraction,
            weeklyFraction: weeklyFraction,
            monthlyFraction: monthlyFraction
        )
        statusItem.button?.title = ""
    }
}
