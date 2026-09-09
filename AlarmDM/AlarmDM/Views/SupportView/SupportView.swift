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

    private enum Donation {
        static let patreon = URL(string: "https://www.patreon.com/daskoimladja")!
        static let payPal = URL(string: "https://www.paypal.com/paypalme/daskoimladja")!
        static let bankName = "OTP Vojvođanska banka"
        static let accountNumber = "325-9300600398707-66"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                intro
                patreonRow
                payPalRow
                bankSection
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

    private var patreonRow: some View {
        Link(destination: Donation.patreon) {
            donationCard(
                title: "Patreon",
                detail: "Stalna mesečna ili godišnja donacija",
                systemImage: "heart.circle.fill"
            )
        }
        .accessibilityLabel("Podrži preko Patreona")
    }

    private var payPalRow: some View {
        Link(destination: Donation.payPal) {
            donationCard(
                title: "PayPal",
                detail: "Jednokratna uplata",
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
                    .foregroundColor(Color("primary"))
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
                        .foregroundColor(Color("primary"))
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color("primary").opacity(0.08))
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(didCopyAccount ? "Broj računa je kopiran" : "Kopiraj broj računa")

            if let qr = UIImage(named: "img_qr_donacije") {
                VStack(spacing: 8) {
                    Image(uiImage: qr)
                        .resizable()
                        .interpolation(.none)
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: 220)
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white))
                    Text("Skeniraj kôd u aplikaciji svoje banke")
                        .font(.caption)
                        .foregroundColor(Color("secondaryText"))
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color("primary").opacity(0.05))
        )
    }

    // MARK: - Building blocks

    private func donationCard(title: String, detail: String, systemImage: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.title)
                .foregroundColor(Color("primary"))

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
                .fill(Color("primary").opacity(0.05))
        )
    }
}

#Preview {
    NavigationStack { SupportView() }
}
