//
//  AvafliV2Winner.swift
//  AvafliSDK
//
//  "WE HAVE A WINNER!" banner + winners dialog, from Joe's Figma
//  (MESSAGE TOAST / WINNER 5297:6015, Modal Property 1=Winner 5289:4525).
//  Shown when the giveaway payload carries a latestWinner.
//

import SwiftUI

// MARK: - Banner (below the header, above the prize card)

struct AvafliV2WinnerBanner: View {
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 0) {
                AvafliV2Asset.trophy
                    .resizable().scaledToFill()
                    .frame(width: 41, height: 54)
                    .clipped()
                    .scaleEffect(x: -1)   // design mirrors the trophy on the toast
                Spacer(minLength: 8)
                VStack(spacing: 0) {
                    Text("WE HAVE A WINNER!")
                        .font(AvafliV2Font.inter(17, .heavy))
                        .kerning(-0.85)
                    Text("Tap to see latest winners.")
                        .font(AvafliV2Font.inter(12))
                        .kerning(-0.6)
                }
                .foregroundColor(.white)
                Spacer(minLength: 8)
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(AvafliV2Color.gunmetal))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .frame(height: 70)
            .background(AvafliV2Color.deepCharcoal)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Winners dialog

struct AvafliV2WinnerModal: View {
    let accent: Color
    let winner: GiveawayWinner
    let onDismiss: () -> Void

    @State private var appeared = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            card
                .scaleEffect(appeared ? 1 : 0.9)
                .opacity(appeared ? 1 : 0)
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: appeared)
        }
        .onAppear { appeared = true }
    }

    private var card: some View {
        VStack(spacing: 7) {
            HStack(alignment: .center, spacing: 0) {
                AvafliV2Asset.trophy
                    .resizable().scaledToFit()
                    .frame(width: 114, height: 153)
                    .rotationEffect(.degrees(-5.96))
                    .frame(width: 129)
                VStack(spacing: 0) {
                    Text("WE HAVE A")
                        .font(AvafliV2Font.inter(23, .bold))
                        .kerning(-1.15)
                        .foregroundColor(.white)
                    Text("WINNER!")
                        .font(AvafliV2Font.inter(44, .black))
                        .kerning(-2.2)
                        .foregroundColor(accent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text("Congratulations to our latest big winner!")
                        .font(AvafliV2Font.inter(15))
                        .kerning(-0.75)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .frame(width: 160)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.top, 24)

            VStack(spacing: 8) {
                Text("LATEST WINNER:")
                    .font(AvafliV2Font.inter(19, .bold))
                    .foregroundColor(.white)
                winnerPill
                VStack(spacing: 3) {
                    if let awarded = winner.awardedAtDisplay {
                        Text("This prize awarded on \(awarded)")
                            .font(AvafliV2Font.inter(16))
                    }
                    Text("All new prize available now! Keep going!")
                        .font(AvafliV2Font.inter(16, .bold))
                }
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
            }
            .padding(.bottom, 22)
        }
        .frame(maxWidth: 380)
        .background(background)
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(accent, lineWidth: 2))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(alignment: .topTrailing) {
            Button(action: onDismiss) {
                Image("avafli-close", bundle: .module)
                    .resizable().scaledToFit()
                    .frame(width: 11, height: 11)
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(AvafliV2Color.gunmetal))
            }
            .buttonStyle(.plain)
            .padding(12)
        }
        .padding(.horizontal, 16)
    }

    /// Gold-sparkle art behind the content (Figma bg export + gold confetti drift).
    private var background: some View {
        ZStack {
            AvafliV2Color.deepCharcoal
            AvafliV2Asset.winnerModalBg
                .resizable().scaledToFill()
                .opacity(0.9)
            LinearGradient(
                colors: [Color.black.opacity(0), Color.black.opacity(0.75)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            AvafliV2ConfettiView(style: .gold, count: 26, speed: 0.7)
        }
    }

    private var winnerPill: some View {
        HStack(spacing: 11) {
            avatar
            VStack(alignment: .leading, spacing: 2) {
                Text(winner.name)
                    .font(AvafliV2Font.inter(20, .bold))
                if let location = winner.location {
                    Text(location)
                        .font(AvafliV2Font.inter(20))
                }
            }
            .foregroundColor(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
        }
        .padding(.leading, 13)
        .padding(.trailing, 20)
        .frame(height: 72)
        .background(
            Capsule()
                .fill(AvafliV2Color.gunmetal)
                .overlay(Capsule().stroke(accent, lineWidth: 2))
        )
    }

    @ViewBuilder private var avatar: some View {
        if let urlString = winner.avatarUrl, let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                if case let .success(image) = phase {
                    image.resizable().scaledToFill()
                } else {
                    initialsCircle
                }
            }
            .frame(width: 51, height: 51)
            .clipShape(Circle())
        } else {
            initialsCircle.frame(width: 51, height: 51)
        }
    }

    private var initialsCircle: some View {
        Circle()
            .fill(accent.opacity(0.35))
            .overlay(
                Text(String(winner.name.prefix(1)))
                    .font(AvafliV2Font.inter(24, .bold))
                    .foregroundColor(.white)
            )
    }
}
