//
//  CelebrationOverlay.swift
//  AvafliSDK
//
//  Burst-particle celebration effect triggered on claim actions.
//  Pure SwiftUI — no UIKit particle emitters or external deps.
//

import SwiftUI

struct CelebrationOverlay: View {
    let isActive: Bool
    let accentColor: Color

    @State private var particles: [Particle] = []

    private struct Particle: Identifiable {
        let id = UUID()
        var x: CGFloat
        var y: CGFloat
        let targetX: CGFloat
        let targetY: CGFloat
        let rotation: Double
        let scale: CGFloat
        let symbol: String
        let color: Color
    }

    private let symbols = ["star.fill", "sparkle", "circle.fill", "flame.fill"]
    private let colors: [Color] = [.yellow, .orange, .white, .green, .cyan]

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(particles) { p in
                    Image(systemName: p.symbol)
                        .font(.system(size: 10 * p.scale, weight: .bold))
                        .foregroundColor(p.color)
                        .position(x: p.x, y: p.y)
                        .rotationEffect(.degrees(p.rotation))
                        .opacity(isActive ? 0 : 1)
                }
            }
            .allowsHitTesting(false)
            .onChange(of: isActive) { newValue in
                if newValue {
                    spawnParticles(in: geo.size)
                    withAnimation(.easeOut(duration: 1.2)) {
                        animateParticles()
                    }
                    // Clean up after animation
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                        particles = []
                    }
                }
            }
        }
        .ignoresSafeArea()
    }

    private func spawnParticles(in size: CGSize) {
        let centerX = size.width / 2
        let centerY = size.height * 0.45
        var newParticles: [Particle] = []

        for _ in 0..<24 {
            let angle = Double.random(in: 0...(2 * .pi))
            let distance = CGFloat.random(in: 80...220)
            let targetX = centerX + cos(angle) * distance
            let targetY = centerY + sin(angle) * distance - CGFloat.random(in: 40...120)

            newParticles.append(Particle(
                x: centerX,
                y: centerY,
                targetX: targetX,
                targetY: targetY,
                rotation: Double.random(in: 0...360),
                scale: CGFloat.random(in: 0.6...1.4),
                symbol: symbols.randomElement()!,
                color: colors.randomElement()!
            ))
        }
        particles = newParticles
    }

    private func animateParticles() {
        for i in particles.indices {
            particles[i].x = particles[i].targetX
            particles[i].y = particles[i].targetY
        }
    }
}

// MARK: - View Modifier for easy attachment

extension View {
    /// Overlay a burst celebration when `trigger` becomes true.
    func celebrationEffect(isActive: Bool, accentColor: Color = .yellow) -> some View {
        overlay(
            CelebrationOverlay(isActive: isActive, accentColor: accentColor)
        )
    }
}
