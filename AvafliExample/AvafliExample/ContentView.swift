//
//  ContentView.swift
//  AvafliExample
//
//  The example app's main screen. The Avafli experience is auto-opened by the
//  SDK once per day — there is no manual launch. Use "Reset demo state" then
//  kill + relaunch the app to see the auto-open again.
//

import SwiftUI
import AvafliSDK

struct ContentView: View {
    
    @State private var isAnimating = false
    @State private var logoIsLoaded = false
    
    var body: some View {
        ZStack {
            // Dynamic gradient background matching Avafli SDK vibe
            LinearGradient(
                colors: [
                    Color(hex: "#020617"),
                    Color(hex: "#1e3a8a"),
                    Color(hex: "#7c3aed")
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            // Floating particles animation (cool factor!)
            ForEach(0..<20) { index in
                Circle()
                    .fill(Color.white.opacity(0.1))
                    .frame(width: CGFloat.random(in: 2...8), height: CGFloat.random(in: 2...8))
                    .position(
                        x: CGFloat.random(in: 0...UIScreen.main.bounds.width),
                        y: CGFloat.random(in: 0...UIScreen.main.bounds.height)
                    )
                    .onAppear {
                        withAnimation(.linear(duration: Double.random(in: 10...20)).repeatForever(autoreverses: true)) {
                            // Subtle float
                        }
                    }
            }
            
            VStack(spacing: 40) {
                // AVAFLI Logo Section (with fallback & debug)
                Group {
                    if logoIsLoaded {
                        // Loaded from the asset catalog ("avafli-logo")
                        Image(uiImage: UIImage(named: "avafli-logo") ?? UIImage())
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 300)
                            .padding(.top, 80)
                            .scaleEffect(isAnimating ? 1.0 : 0.8)
                            .opacity(isAnimating ? 1.0 : 0.5)
                            .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: isAnimating)
                    } else {
                        // Fallback: Styled text logo
                        Text("AVAFLI")
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.white, Color(hex: "#7c3aed")],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(height: 120)
                            .scaleEffect(isAnimating ? 1.0 : 0.8)
                            .opacity(isAnimating ? 1.0 : 0.5)
                            .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: isAnimating)
                    }
                }
                
                // Welcome Text (bold, glowing)
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text("Welcome to the ")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.white, .blue.opacity(0.8)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .shadow(color: .blue.opacity(0.3), radius: 10)

                    Text("Avafli")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.white, .blue.opacity(0.8)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .shadow(color: .blue.opacity(0.3), radius: 10)

                    Text("™")
                        .font(.system(size: 16, weight: .bold, design: .rounded))  // Smaller, but bold
                        .foregroundColor(.white.opacity(0.9))
                        .baselineOffset(6)  // Perfectly aligns with cap height of Avafli
                        .shadow(color: .blue.opacity(0.3), radius: 8)

                    Text(" iOS SDK")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.white, .blue.opacity(0.8)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .shadow(color: .blue.opacity(0.3), radius: 10)
                }
                .multilineTextAlignment(.center)
                .opacity(isAnimating ? 1.0 : 0.0)
                .scaleEffect(isAnimating ? 1.0 : 0.9)
                .animation(.easeOut(duration: 1.0).delay(0.5), value: isAnimating)
                
                // The experience opens itself — once per day, driven by the SDK.
                HStack(spacing: 12) {
                    Image(systemName: "sparkles")
                        .font(.title2)
                        .foregroundStyle(.white)

                    Text("Avafli opens itself once per day")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 24)
                        .fill(.white.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 24)
                                .stroke(.white.opacity(0.2), lineWidth: 1)
                        )
                )
                .scaleEffect(isAnimating ? 1.0 : 0.0)
                .animation(.spring(response: 0.6, dampingFraction: 0.8).delay(1.0), value: isAnimating)

                // DEMO: clears the SDK's once-per-day auto-present mark and the
                // unregistered impression counter so the team can re-test the V2
                // auto-open flow without waiting for tomorrow. Kill + relaunch the
                // app after tapping — the drawer will auto-present again.
                Button(action: resetDemoState) {
                    Label("Reset demo state (auto-open again)", systemImage: "arrow.counterclockwise")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .opacity(isAnimating ? 1.0 : 0.0)
                .animation(.easeOut(duration: 1.0).delay(1.3), value: isAnimating)

                // DEMO CONTROLS — each action re-arms auto-open; kill + relaunch
                // the app afterwards to see the corresponding flow.
                VStack(spacing: 12) {
                    demoButton("person.badge.plus", "New demo user (start from email capture)") {
                        Avafli.demoWipeIdentity()
                        demoStatus = "Fresh user ready — relaunch the app"
                    }
                    demoButton("calendar.badge.clock", "Reset today's claim (show daily claim UX)") {
                        Avafli.demoPerform("resetClaim") { ok in
                            demoStatus = ok ? "Claim reset — relaunch the app" : "Failed — is the demo user registered?"
                        }
                    }
                    demoButton("trophy", "Make me the winner (show winner flow)") {
                        Avafli.demoPerform("makeWinner") { ok in
                            demoStatus = ok ? "You're the winner — relaunch the app" : "Failed — is the demo user registered?"
                        }
                    }
                    demoButton("trash", "Clear winner state (back to dashboard)") {
                        Avafli.demoPerform("clearWinner") { ok in
                            demoStatus = ok ? "Winner cleared — relaunch the app" : "Failed — is the demo user registered?"
                        }
                    }
                    if let demoStatus {
                        Text(demoStatus)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(.green)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.top, 8)
                .opacity(isAnimating ? 1.0 : 0.0)
                .animation(.easeOut(duration: 1.0).delay(1.4), value: isAnimating)

                Spacer()
                Text("© 2026 AVAFLI • All rights reserved.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
            }
            .padding()
        }
        .onAppear {
            // Debug logo loading
            if UIImage(named: "avafli-logo") != nil {
                print("✅ AVAFLI logo found in asset catalog")
                logoIsLoaded = true
            } else {
                print("❌ AVAFLI logo not found! Check: 1) Asset name 'avafli-logo', 2) Target membership, 3) Clean build.")
                logoIsLoaded = false
            }
            isAnimating = true
        }
    }
    
    @State private var demoStatus: String?

    private func demoButton(_ icon: String, _ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.08)))
        }
    }

    private func resetDemoState() {
        // The SDK namespaces its auto-present bookkeeping by bundle id.
        let bundleId = Bundle.main.bundleIdentifier ?? "com.avafli.winr.example"
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "winr_last_auto_present_\(bundleId)")
        defaults.removeObject(forKey: "winr_unregistered_impressions_\(bundleId)")
        print("🔄 Avafli demo state reset — kill and relaunch the app to see auto-open again")
    }
}

// MARK: - Hex Color Extension
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

#Preview {
    ContentView()
}
