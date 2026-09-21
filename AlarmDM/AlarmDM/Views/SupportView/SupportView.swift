//
//  SupportView.swift
//  AlarmDM
//
//  The Podrži tab. Donations are handled outside the app — the buttons open
//  Patreon and PayPal in the browser, and the bank details can be copied or
//  scanned. Nothing here unlocks anything in the app, which is what keeps it
//  out of in-app purchase territory.
//

import SwiftUI
import UIKit

struct SupportView: View {

    @State private var didCopyAccount = false
    @State private var isShowingFullscreenQR = false

    private enum Donation {
        static let patreon = URL(string: "https://www.patreon.com/daskoimladja")!
        static let payPal = URL(string: "https://www.paypal.com/paypalme/daskoimladja")!
        static let bankName = "OTP banka"
        static let accountNumber = "325-9300600398707-66"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                intro

                sectionHeader(String(localized: "Daško i Mlađa"))
                patreonRow
                payPalRow
                bankSection

                if !Show.withOwnPatreon.isEmpty {
                    sectionHeader(String(localized: "Emisije"))
                    showPatreonSection
                }
            }
            .padding(20)
        }
        .background(Color("background").ignoresSafeArea())
        .navigationTitle("Podrži")
    }

    // MARK: - Sections

    private var intro: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Naš rad u potpunosti zavisi od vaših donacija.")
                .font(.headline)
                .foregroundColor(Color("primaryText"))
            Text("Možeš nas podržati na sledeće načine:")
                .font(.subheadline)
                .foregroundColor(Color("secondaryText"))
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.caption.weight(.semibold))
            .kerning(0.6)
            .foregroundColor(Color("secondaryText"))
            .padding(.top, 4)
    }

    /// Several shows raise money separately from the station.
    private var showPatreonSection: some View {
        VStack(spacing: 12) {
            ForEach(Show.withOwnPatreon, id: \.self) { show in
                if let url = show.patreonURL {
                    Link(destination: url) {
                        HStack(spacing: 14) {
                            Image(show.imageName)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 44, height: 44)
                                .clipShape(RoundedRectangle(cornerRadius: 8))

                            VStack(alignment: .leading, spacing: 2) {
                                Text(show.displayName)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(Color("primaryText"))
                                    .lineLimit(1)
                                Text("Patreon")
                                    .font(.caption)
                                    .foregroundColor(Color("secondaryText"))
                            }

                            Spacer(minLength: 0)

                            Image(systemName: "arrow.up.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundColor(Color("secondaryText"))
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Color(.secondarySystemBackground))
                        )
                    }
                    .accessibilityLabel("Podrži \(show.displayName) na Patreonu")
                }
            }
        }
    }

    private var patreonRow: some View {
        Link(destination: Donation.patreon) {
            donationCard(
                title: "Patreon",
                detail: String(localized: "Stalna mesečna ili godišnja donacija"),
                systemImage: "heart.circle.fill"
            )
        }
        .accessibilityLabel("Podrži preko Patreona")
    }

    private var payPalRow: some View {
        Link(destination: Donation.payPal) {
            donationCard(
                title: "PayPal",
                detail: String(localized: "Jednokratna uplata"),
                systemImage: "creditcard.circle.fill"
            )
        }
        .accessibilityLabel("Podrži preko PayPala")
    }

    private var bankSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                Image(systemName: "building.columns.circle.fill")
                    .font(.title)
                    .foregroundColor(Color("primaryLink"))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Uplata na račun")
                        .font(.headline)
                        .foregroundColor(Color("primaryText"))
                    Text(Donation.bankName)
                        .font(.subheadline)
                        .foregroundColor(Color("secondaryText"))
                }
            }

            Button {
                UIPasteboard.general.string = Donation.accountNumber
                withAnimation { didCopyAccount = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    withAnimation { didCopyAccount = false }
                }
            } label: {
                HStack {
                    Text(Donation.accountNumber)
                        .font(.body.monospacedDigit())
                        .foregroundColor(Color("primaryText"))
                    Spacer()
                    Image(systemName: didCopyAccount ? "checkmark" : "doc.on.doc")
                        .foregroundColor(Color("primaryLink"))
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.tertiarySystemFill))
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(didCopyAccount ? "Broj računa je kopiran" : "Kopiraj broj računa")

            if let qr = UIImage(named: "img_qr_donacije") {
                VStack(spacing: 8) {
                    Button {
                        isShowingFullscreenQR = true
                    } label: {
                        Image(uiImage: qr)
                            .resizable()
                            .interpolation(.none)
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: 220)
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Prikaži kôd preko celog ekrana")

                    VStack(spacing: 3) {
                        Label("Klikni na kôd za skeniranje", systemImage: "arrow.up.left.and.arrow.down.right")
                            .font(.caption.weight(.medium))
                            .foregroundColor(Color("primaryLink"))
                        Text("Kôd nosi unapred upisan iznos od 500 RSD.")
                            .font(.caption)
                            .multilineTextAlignment(.center)
                            .foregroundColor(Color("secondaryText"))
                    }
                }
                .frame(maxWidth: .infinity)
                .fullScreenCover(isPresented: $isShowingFullscreenQR) {
                    FullscreenQRView(image: qr)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemBackground))
        )
    }

    // MARK: - Building blocks

    private func donationCard(title: String, detail: String, systemImage: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.title)
                .foregroundColor(Color("primaryLink"))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(Color("primaryText"))
                Text(detail)
                    .font(.subheadline)
                    .foregroundColor(Color("secondaryText"))
            }

            Spacer(minLength: 0)

            Image(systemName: "arrow.up.right")
                .font(.footnote.weight(.semibold))
                .foregroundColor(Color("secondaryText"))
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemBackground))
        )
    }
}

#Preview {
    NavigationStack { SupportView() }
}

// MARK: - Fullscreen QR

/// Big and bright, so someone else can scan it off the screen. Phones dim
/// themselves and a dim screen is the usual reason a scan fails.
private struct FullscreenQRView: View {
    let image: UIImage

    @Environment(\.dismiss) private var dismiss
    @State private var previousBrightness = FullscreenQRView.screenBrightness

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                Image(uiImage: image)
                    .resizable()
                    .interpolation(.none)
                    .aspectRatio(contentMode: .fit)
                    .padding(.horizontal, 32)

                VStack(spacing: 4) {
                    Text("325-9300600398707-66")
                        .font(.callout.monospacedDigit())
                    Text("OTP banka · 500 RSD")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button("Zatvori") { dismiss() }
                    .font(.body.weight(.medium))
                    .padding(.bottom, 24)
            }
            .foregroundColor(.black)
        }
        .onAppear {
            previousBrightness = FullscreenQRView.screenBrightness
            FullscreenQRView.setScreenBrightness(1.0)
        }
        .onDisappear {
            FullscreenQRView.setScreenBrightness(previousBrightness)
        }
    }

    // Turning the screen up is how a QR code gets scanned across a table. The
    // Mac neither allows it nor needs it: its display is not being held up to
    // someone else's camera.

    private static var screenBrightness: CGFloat {
        #if targetEnvironment(macCatalyst)
        return 1
        #else
        return UIScreen.main.brightness
        #endif
    }

    private static func setScreenBrightness(_ value: CGFloat) {
        #if !targetEnvironment(macCatalyst)
        UIScreen.main.brightness = value
        #endif
    }
}
