import AppKit

final class LoginWindowController: NSWindowController {
    var onLogin: ((String, String) -> Void)?

    private let emailField = NSTextField()
    private let passwordField = NSSecureTextField()
    private let statusLabel = NSTextField(labelWithString: "")
    private let loginButton = NSButton(title: "登录", target: nil, action: nil)

    init(savedEmail: String?) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 390, height: 230),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Owl Codex Monitor"
        window.center()
        window.isReleasedWhenClosed = false
        super.init(window: window)

        let content = NSView(frame: window.contentView!.bounds)
        content.translatesAutoresizingMaskIntoConstraints = false
        window.contentView = content

        let title = NSTextField(labelWithString: "登录 Owl AI")
        title.font = .systemFont(ofSize: 18, weight: .semibold)
        let subtitle = NSTextField(labelWithString: "登录凭据和刷新令牌仅保存在本机 macOS Keychain。")
        subtitle.font = .systemFont(ofSize: 11)
        subtitle.textColor = .secondaryLabelColor

        emailField.placeholderString = "邮箱"
        emailField.stringValue = savedEmail ?? ""
        passwordField.placeholderString = "密码"
        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .systemRed

        loginButton.target = self
        loginButton.action = #selector(loginTapped)
        loginButton.keyEquivalent = "\r"

        let stack = NSStackView(views: [title, subtitle, emailField, passwordField, statusLabel, loginButton])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)

        emailField.widthAnchor.constraint(equalToConstant: 330).isActive = true
        passwordField.widthAnchor.constraint(equalToConstant: 330).isActive = true
        loginButton.widthAnchor.constraint(equalToConstant: 90).isActive = true
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 30),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -30),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 24)
        ])
    }

    required init?(coder: NSCoder) { nil }

    func showError(_ message: String) {
        statusLabel.stringValue = message
        loginButton.isEnabled = true
        emailField.isEnabled = true
        passwordField.isEnabled = true
    }

    func finishLogin() {
        close()
        passwordField.stringValue = ""
    }

    @objc private func loginTapped() {
        let email = emailField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let password = passwordField.stringValue
        guard !email.isEmpty, !password.isEmpty else {
            showError("请输入邮箱和密码")
            return
        }
        statusLabel.stringValue = "正在登录..."
        statusLabel.textColor = .secondaryLabelColor
        loginButton.isEnabled = false
        emailField.isEnabled = false
        passwordField.isEnabled = false
        onLogin?(email, password)
    }
}
