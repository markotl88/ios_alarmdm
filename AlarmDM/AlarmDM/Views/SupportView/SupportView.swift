//
//  SupportView.swift
//  AlarmDM
//
//  The Podrži tab. Donations are handled outside the app - the buttons open
//  Patreon and PayPal in the browser, and the bank details can be copied or
//  scanned. Nothing here unlocks anything in the app, which is what keeps it
//  out of in-app purchase territory.
//

import SwiftUI
import UIKit

// MARK: - Who the money goes to

/// Somebody who can be given money, and the ways there are of doing it.
///
/// The screen used to be sorted two ways at once: the top by method - Patreon,
/// PayPal, the account - and the bottom by recipient, a row per show. That held
/// only while a show had exactly one way to be paid, and it stopped holding the
/// day a show had a code of its own. Giving every show the full treatment would
/// have buried the station under five of them.
///
/// So everybody is the same shape now, and what says who comes first is how
/// much of it is already open: the station asks for no taps, a show asks for
/// one.
struct SupportTarget: Identifiable {
    let id: String
    let name: String
    /// The picture beside the name in a list of several. The station has the
    /// top of the page to itself and needs none.
    var artwork: String?
    /// What to say under the name instead of listing the ways of paying,
    /// which for the station would only name what is spread out underneath it
    /// anyway. What a show's row needs to say is what it holds; what the
    /// station's needs to say is who it is for.
    var tagline: String?
    var patreon: URL?
    var payPal: URL?
    var bank: BankDetails?

    var isWorthShowing: Bool { patreon != nil || payPal != nil || bank != nil }

    /// What the folded row says it holds, so the page still lists what is
    /// there without being as long as it would be with everything open.
    var waysOfPaying: String {
        var ways: [String] = []
        if patreon != nil { ways.append("Patreon") }
        if payPal != nil { ways.append("PayPal") }
        if bank != nil { ways.append(String(localized: "uplata na račun")) }
        return ways.joined(separator: " · ")
    }

    /// What it takes to pay somebody here: the account, whose it is, and the
    /// code that fills a banking app in on your behalf.
    struct BankDetails {
        let bankName: String
        /// Given when the account is a person's rather than the station's -
        /// which is what a banking app will show, and what somebody about to
        /// send money to a stranger's number will want to see first.
        var holder: String?
        let account: String
        var qrAsset: String?
        /// Written into the code when the code carries an amount.
        var qrAmount: String?

        /// The line under a code held up to somebody else's camera.
        var caption: String {
            guard let qrAmount else { return bankName }
            return "\(bankName) · \(qrAmount)"
        }

        /// The bank, and whose account it is when that is worth saying.
        var subtitle: String {
            guard let holder else { return bankName }
            return "\(bankName) · \(holder)"
        }
    }
}

extension SupportTarget {

    static let station = SupportTarget(
        id: "daskoimladja",
        name: String(localized: "Daško i Mlađa"),
        artwork: "iTunesArtwork",
        // A name, so it is not translated and not put through the catalogue.
        tagline: "Alarm",
        patreon: URL(string: "https://www.patreon.com/daskoimladja"),
        payPal: URL(string: "https://www.paypal.com/paypalme/daskoimladja"),
        bank: BankDetails(
            bankName: "OTP banka",
            account: "325-9300600398707-66",
            qrAsset: "img_qr_donacije",
            qrAmount: "500 RSD"
        )
    )

    /// The shows that raise money of their own, in the order the Shows tab
    /// lists them - so this page reads the same way.
    static var shows: [SupportTarget] {
        Show.listed.compactMap { show in
            let target = SupportTarget(
                id: show.rawValue,
                name: show.displayName,
                artwork: show.imageName,
                patreon: show.patreonURL,
                bank: show.supportBank
            )
            return target.isWorthShowing ? target : nil
        }
    }
}

private extension Show {
    /// A show collecting on an account of its own. The station's account is
    /// not repeated here - it belongs to SupportTarget.station.
    var supportBank: SupportTarget.BankDetails? {
        switch self {
        case .unutrasnjaEmigracija:
            return SupportTarget.BankDetails(
                bankName: "Raiffeisen banka",
                holder: "Ivan Varnju",
                // Written out the way a bank does, in threes and thirteens
                // and twos. The code carries the plain digits - that is for a
                // machine, and this is not.
                account: "265-0000001011127-10",
                qrAsset: "img_qr_unutrasnja",
                qrAmount: "500 RSD"
            )
        default:
            return nil
        }
    }
}

/// A code opened over the whole screen. The asset name identifies it, which is
/// what keeps one cover from being asked to show two different codes.
private struct ZoomedCode: Identifiable {
    let id: String
    let image: UIImage
    let account: String
    let caption: String
}

// MARK: - The screen

struct SupportView: View {
    @Environment(\.horizontalSizeClass) private var widthClass

    /// Which account was copied, not whether one was: there is more than one
    /// on the page now, and only the one that was pressed should say so.
    @State private var copiedAccount: String?
    @State private var zoomed: ZoomedCode?
    @State private var opened: Set<String> = []

    private let station = SupportTarget.station
    private let shows = SupportTarget.shows

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if widthClass == .regular {
                    Text("Podrži")
                        .font(.largeTitle.bold())
                        .accessibilityAddTraits(.isHeader)
                }

                intro

                stationBlock

                if !shows.isEmpty {
                    sectionHeader(String(localized: "Emisije"))
                    VStack(spacing: 12) {
                        ForEach(shows) { showRow($0) }
                    }
                }
            }
            .padding(20)
        }
        .background(Color("background").ignoresSafeArea())
        .navigationTitle(widthClass == .regular ? Text(verbatim: "") : Text("Podrži"))
        .navigationBarTitleDisplayMode(widthClass == .regular ? .inline : .automatic)
        .fullScreenCover(item: $zoomed) { code in
            FullscreenQRView(image: code.image, account: code.account, caption: code.caption)
        }
    }

    // MARK: - Sections

    private var intro: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Naš rad u potpunosti zavisi od tvojih donacija.")
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

    /// Open, always, and first. Nothing about it is behind a tap.
    private var stationBlock: some View {
        VStack(spacing: 12) {
            identityRow(station, isOpen: nil)
                .accessibilityElement(children: .combine)
                .padding(.bottom, 2)

            if let url = station.patreon {
                Link(destination: url) {
                    donationCard(
                        title: "Patreon",
                        detail: String(localized: "Redovna mesečna ili godišnja donacija")
                    ) {
                        brandMark("logo_patreon", diameter: 30)
                    }
                }
                .accessibilityLabel("Podrži preko Patreona")
            }

            if let url = station.payPal {
                Link(destination: url) {
                    donationCard(
                        title: "PayPal",
                        detail: String(localized: "Jednokratna uplata")
                    ) {
                        brandMark("logo_paypal", diameter: 30)
                    }
                }
                .accessibilityLabel("Podrži preko PayPala")
            }

            if let bank = station.bank {
                bankDetails(bank)
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(.secondarySystemBackground))
                    )
            }
        }
    }

    /// A show, folded shut.
    private func showRow(_ target: SupportTarget) -> some View {
        let isOpen = opened.contains(target.id)

        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.22)) {
                    if isOpen { opened.remove(target.id) } else { opened.insert(target.id) }
                }
            } label: {
                identityRow(target, isOpen: isOpen)
                    .padding(12)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Podrži \(target.name)")
            .accessibilityValue(target.waysOfPaying)
            .accessibilityHint(isOpen ? "Dodirni da zatvoriš" : "Dodirni da otvoriš")

            if isOpen {
                VStack(spacing: 14) {
                    if let url = target.patreon {
                        Link(destination: url) {
                            HStack(spacing: 10) {
                                brandMark("logo_patreon", diameter: 24)
                                    .frame(width: 24)
                                Text("Patreon")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundColor(Color("primaryText"))
                                Spacer(minLength: 0)
                                Image(systemName: "arrow.up.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(Color("secondaryText"))
                            }
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color(.tertiarySystemFill))
                            )
                        }
                        .accessibilityLabel("Podrži \(target.name) na Patreonu")
                    }

                    if let bank = target.bank {
                        bankDetails(bank)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 14)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(.secondarySystemBackground))
        )
    }

    // MARK: - Building blocks

    /// Who this is: the same picture and name for the station as for a show.
    ///
    /// The station used to be a line of small capitals while every show had a
    /// face - the one recipient this page is mostly about, and the only one
    /// without a picture. `isOpen` is nil for the station, which does not fold
    /// and so has no arrow to turn.
    private func identityRow(_ target: SupportTarget, isOpen: Bool?) -> some View {
        let isStation = isOpen == nil
        let side: CGFloat = isStation ? 52 : 44

        return HStack(spacing: 14) {
            if let artwork = target.artwork {
                Image(artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: side, height: side)
                    .clipShape(RoundedRectangle(cornerRadius: isStation ? 12 : 8, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: target.name)
                    .font(isStation ? .title3.weight(.semibold) : .subheadline.weight(.semibold))
                    .foregroundColor(Color("primaryText"))
                    .lineLimit(1)
                Text(verbatim: target.tagline ?? target.waysOfPaying)
                    .font(.caption)
                    .foregroundColor(Color("secondaryText"))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .multilineTextAlignment(.leading)

            Spacer(minLength: 0)

            if let isOpen {
                Image(systemName: "chevron.down")
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(Color("secondaryText"))
                    .rotationEffect(.degrees(isOpen ? 180 : 0))
            }
        }
    }

    /// The account and its code. In a card of its own under the station, and
    /// inside the row when a show is opened - the same thing either way, which
    /// is the point of the shape.
    @ViewBuilder
    private func bankDetails(_ bank: SupportTarget.BankDetails) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                Image(systemName: "building.columns.circle.fill")
                    .font(.title)
                    .foregroundColor(Color("primaryLink"))
                    .frame(width: Self.iconColumn)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Uplata na račun")
                        .font(.headline)
                        .foregroundColor(Color("primaryText"))
                    Text(verbatim: bank.subtitle)
                        .font(.subheadline)
                        .foregroundColor(Color("secondaryText"))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            copyRow(bank.account)

            if let assetName = bank.qrAsset, let qr = UIImage(named: assetName) {
                codeBlock(qr, assetName: assetName, bank: bank)
            }
        }
    }

    /// A brand's own mark on a disc of ours.
    ///
    /// Both marks ship as templates - the shape, with nothing behind it - so
    /// what they are drawn on is a decision rather than whatever came with
    /// the file. What came with the files were tiles: Patreon's black,
    /// PayPal's charcoal, and on this screen in the dark that is a dark
    /// square on a dark card. They sit on the app's blue instead, the same
    /// circle the symbols beside them are drawn in.
    ///
    /// White, and one colour, for both. PayPal's is their reversed monogram -
    /// the one they publish for dark backgrounds - rather than the two-tone
    /// one flattened, which would have been a different mark and not theirs.
    private func brandMark(_ asset: String, diameter: CGFloat) -> some View {
        Circle()
            .fill(Color("primaryLink"))
            .frame(width: diameter, height: diameter)
            .overlay {
                Image(asset)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: diameter, height: diameter)
                    .foregroundColor(.white)
            }
            .accessibilityHidden(true)
    }

    private func copyRow(_ account: String) -> some View {
        let isCopied = copiedAccount == account

        return Button {
            UIPasteboard.general.string = account
            withAnimation { copiedAccount = account }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                withAnimation {
                    // Only if nothing else has been copied since.
                    if copiedAccount == account { copiedAccount = nil }
                }
            }
        } label: {
            HStack {
                Text(verbatim: account)
                    .font(.body.monospacedDigit())
                    .foregroundColor(Color("primaryText"))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer()
                Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                    .foregroundColor(Color("primaryLink"))
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.tertiarySystemFill))
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isCopied ? "Broj računa je kopiran" : "Kopiraj broj računa")
    }

    private func codeBlock(_ qr: UIImage, assetName: String, bank: SupportTarget.BankDetails) -> some View {
        VStack(spacing: 8) {
            Button {
                zoomed = ZoomedCode(id: assetName, image: qr, account: bank.account, caption: bank.caption)
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
                Label("Dodirni kôd za uvećani prikaz", systemImage: "arrow.up.left.and.arrow.down.right")
                    .font(.caption.weight(.medium))
                    .foregroundColor(Color("primaryLink"))
                if let amount = bank.qrAmount {
                    Text("U kôd je unapred upisan iznos od \(amount).")
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .foregroundColor(Color("secondaryText"))
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// How wide the icon is allowed to be, everywhere on this screen.
    ///
    /// The discs are drawn to a size and the symbols to a font, and those two
    /// do not land on the same number - so the text beside them started a
    /// point or two further along in one card than in the next. A column
    /// they all sit in the middle of gives every line one left edge.
    private static let iconColumn: CGFloat = 30

    private func donationCard<Icon: View>(
        title: String,
        detail: String,
        @ViewBuilder icon: () -> Icon
    ) -> some View {
        HStack(spacing: 14) {
            icon()
                .frame(width: Self.iconColumn)

            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: title)
                    .font(.headline)
                    .foregroundColor(Color("primaryText"))
                Text(verbatim: detail)
                    .font(.subheadline)
                    .foregroundColor(Color("secondaryText"))
                    // A detail long enough to wrap was setting its second
                    // line centred under the first, which read as a paragraph
                    // that had lost its left edge. Said here rather than
                    // inherited from whatever is above it.
                    .fixedSize(horizontal: false, vertical: true)
            }
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)

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
    let account: String
    /// The bank, and the amount when the code carries one.
    let caption: String

    @Environment(\.dismiss) private var dismiss
    @State private var previousBrightness = FullscreenQRView.screenBrightness
    @State private var dragOffset: CGFloat = 0

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            VStack(spacing: 24) {
                // The same handle every sheet has, so the pull down below is
                // something the screen offers rather than something to guess.
                Capsule()
                    .fill(Color.black.opacity(0.18))
                    .frame(width: 36, height: 5)
                    .padding(.top, 10)

                Spacer()

                Image(uiImage: image)
                    .resizable()
                    .interpolation(.none)
                    .aspectRatio(contentMode: .fit)
                    .padding(.horizontal, 32)

                VStack(spacing: 4) {
                    Text(verbatim: account)
                        .font(.callout.monospacedDigit())
                    Text(verbatim: caption)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button("Zatvori") { dismiss() }
                    .font(.body.weight(.medium))
                    .padding(.bottom, 24)
            }
            .foregroundColor(.black)
            .offset(y: dragOffset)
            // Held up to somebody else's phone across a table, this is the
            // screen most likely to be put away in a hurry, and a hand coming
            // back down the screen is the quickest way to do it. The white
            // stays put underneath so nothing dark shows through at the top.
            .gesture(
                DragGesture()
                    .onChanged { value in
                        if value.translation.height > 0 { dragOffset = value.translation.height }
                    }
                    .onEnded { value in
                        if value.translation.height > 120 {
                            dismiss()
                        }
                        withAnimation { dragOffset = 0 }
                    }
            )
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
