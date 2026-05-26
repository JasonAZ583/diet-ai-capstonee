import SwiftUI
import AVFoundation

struct BarcodeView: View {
    @StateObject private var vm = BarcodeViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var scanLineOffset: CGFloat = 0
    @State private var cameraAuth: AVAuthorizationStatus = .notDetermined

    var body: some View {
        ZStack {
            // Camera feed (real device) or radial-gradient mock (simulator).
            cameraOrMock
                .ignoresSafeArea()

            // Dim overlay so the chrome reads on top of camera.
            LinearGradient(
                colors: [.black.opacity(0.55), .black.opacity(0.15), .black.opacity(0.55)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 24)
                    .padding(.top, 18)

                Spacer(minLength: 0)

                viewfinder
                    .frame(width: 280, height: 200)

                Spacer(minLength: 0)

                statusPill
                    .padding(.bottom, 110)
            }

            // Bottom sheet (found / not found / added)
            VStack {
                Spacer()
                bottomSheet
            }
            .ignoresSafeArea(edges: .bottom)
        }
        .background(Color.black.ignoresSafeArea())
        .onAppear { startScanLine() }
    }

    // MARK: - Camera / mock background

    @ViewBuilder
    private var cameraOrMock: some View {
        #if targetEnvironment(simulator)
        // Simulator has no camera — use the design's mock gradient and auto-fire a known
        // good barcode after a short delay so the demo still flows.
        ZStack {
            RadialGradient(
                colors: [
                    Color(red: 26/255, green: 26/255, blue: 26/255),
                    .black,
                ],
                center: UnitPoint(x: 0.5, y: 0.6), startRadius: 20, endRadius: 380
            )
        }
        .task(id: ScanIdent(stage: vm.stage)) {
            // Only auto-fire while we're in the scanning state.
            if case .scanning = vm.stage {
                try? await Task.sleep(nanoseconds: 2_400_000_000)
                if case .scanning = vm.stage {
                    // Nutella — present in the bundled OFF parquet.
                    await vm.onScan(code: "0009800800049")
                }
            }
        }
        #else
        switch cameraAuth {
        case .authorized:
            if case .scanning = vm.stage {
                BarcodeScannerView(
                    onCode: { code in Task { await vm.onScan(code: code) } },
                    onError: { _ in }
                )
            } else {
                Color.black
            }
        case .notDetermined:
            // Show the gradient mock while the OS permission prompt is up.
            Color.black
                .overlay(ProgressView().tint(Deck.accent))
                .task { await requestCameraPermission() }
        case .denied, .restricted:
            CameraDeniedOverlay {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } onCancel: {
                dismiss()
            }
        @unknown default:
            Color.black
        }
        #endif
    }

    @MainActor
    private func requestCameraPermission() async {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        if status == .notDetermined {
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            cameraAuth = granted ? .authorized : .denied
        } else {
            cameraAuth = status
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Button {
                    dismiss()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                        Text("close")
                            .font(.deckMono(12))
                    }
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(.top, 4)

            MonoCaption(text: "POST /api/barcode/{barcode}/add", color: .white.opacity(0.55))
                .padding(.top, 14)
            Text("Scan the label.")
                .font(.deckSerif(30))
                .foregroundStyle(.white)
                .tracking(-0.5)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Viewfinder

    private var viewfinder: some View {
        ZStack {
            // Dim the area outside the viewfinder a touch
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.black.opacity(0.18))

            // Scan line
            if case .scanning = vm.stage {
                Rectangle()
                    .fill(Deck.accent)
                    .frame(height: 2)
                    .shadow(color: Deck.accent, radius: 8)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .offset(y: scanLineOffset)
                    .animation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true), value: scanLineOffset)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            }

            // Corner ticks
            CornerTicks(color: Deck.accent, length: 22, thickness: 2)
                .padding(0)

            // Outline
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        }
    }

    private func startScanLine() {
        scanLineOffset = 0
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            scanLineOffset = 200 - 2
        }
    }

    // MARK: - Status pill

    @ViewBuilder
    private var statusPill: some View {
        switch vm.stage {
        case .scanning:
            pill(
                icon: AnyView(
                    Circle().fill(Deck.accent)
                        .frame(width: 10, height: 10)
                        .shadow(color: Deck.accent, radius: 6)
                ),
                text: "Looking for a barcode…"
            )
        case .lookingUp:
            pill(
                icon: AnyView(ProgressView().tint(Deck.accent)),
                text: "Looking up · openfoodfacts.org"
            )
        default:
            EmptyView()
        }
    }

    private func pill(icon: AnyView, text: String) -> some View {
        HStack(spacing: 10) {
            icon
            Text(text)
                .font(.deckMono(12))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .liquidGlass(in: Capsule())
    }

    // MARK: - Bottom sheet

    @ViewBuilder
    private var bottomSheet: some View {
        switch vm.stage {
        case .found(let product):
            FoundSheet(
                product: product,
                isAdding: false,
                onAdd: { qty in Task { await vm.addCurrent(quantity: qty) } },
                onDismiss: { vm.resetToScan() }
            )
            .transition(.move(edge: .bottom))
        case .adding:
            // Reuse the FoundSheet visuals but show spinner button — re-render last product.
            // Easier: show a thin "Adding…" sheet variant.
            AddingSheet()
                .transition(.move(edge: .bottom))
        case .added(let item):
            AddedSheet(item: item, onDone: { dismiss() })
                .transition(.move(edge: .bottom))
        case .notFound(let code):
            NotFoundSheet(code: code, onScanAgain: { vm.resetToScan() }, onDismiss: { dismiss() })
                .transition(.move(edge: .bottom))
        case .error(let msg):
            NotFoundSheet(code: msg, onScanAgain: { vm.resetToScan() }, onDismiss: { dismiss() })
                .transition(.move(edge: .bottom))
        case .scanning, .lookingUp:
            EmptyView()
        }
    }
}

// MARK: - Corner ticks

private struct CornerTicks: View {
    let color: Color
    let length: CGFloat
    let thickness: CGFloat

    var body: some View {
        ZStack {
            // Top-left
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    Rectangle().fill(color).frame(width: length, height: thickness)
                    Spacer()
                }
                HStack(spacing: 0) {
                    Rectangle().fill(color).frame(width: thickness, height: length - thickness)
                    Spacer()
                }
                Spacer()
            }
            // Top-right
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    Spacer()
                    Rectangle().fill(color).frame(width: length, height: thickness)
                }
                HStack(spacing: 0) {
                    Spacer()
                    Rectangle().fill(color).frame(width: thickness, height: length - thickness)
                }
                Spacer()
            }
            // Bottom-left
            VStack(spacing: 0) {
                Spacer()
                HStack(spacing: 0) {
                    Rectangle().fill(color).frame(width: thickness, height: length - thickness)
                    Spacer()
                }
                HStack(spacing: 0) {
                    Rectangle().fill(color).frame(width: length, height: thickness)
                    Spacer()
                }
            }
            // Bottom-right
            VStack(spacing: 0) {
                Spacer()
                HStack(spacing: 0) {
                    Spacer()
                    Rectangle().fill(color).frame(width: thickness, height: length - thickness)
                }
                HStack(spacing: 0) {
                    Spacer()
                    Rectangle().fill(color).frame(width: length, height: thickness)
                }
            }
        }
    }
}

// MARK: - Sheets

private struct FoundSheet: View {
    let product: BarcodeProduct
    let isAdding: Bool
    let onAdd: (Double) -> Void
    let onDismiss: () -> Void

    @State private var quantity: Double = 1

    private var servingGrams: Double {
        product.serving_size > 0 ? product.serving_size : 100
    }
    private var totalGrams: Double { quantity * servingGrams }
    private var totalKcal: Double { quantity * product.calories * servingGrams / 100 }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                MonoCaption(text: "Found · \(product.barcode ?? "—")", color: Deck.accent)
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .foregroundStyle(Deck.muted)
                }
                .buttonStyle(.plain)
            }
            Text(product.name)
                .font(.deckSerif(26))
                .foregroundStyle(Deck.text)
                .lineLimit(2)
            if let brand = product.brand, !brand.isEmpty {
                Text(brand)
                    .font(.deckMono(12))
                    .foregroundStyle(Deck.muted)
            }

            HStack {
                MacroCell(label: "kcal / 100g", value: Int(product.calories.rounded()))
                MacroCell(label: "P", value: Int(product.protein.rounded()))
                MacroCell(label: "C", value: Int(product.carbs.rounded()))
                MacroCell(label: "F", value: Int(product.fat.rounded()))
            }
            .padding(14)
            .background(Deck.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Deck.rule))

            // Servings stepper
            VStack(alignment: .leading, spacing: 8) {
                MonoCaption(text: "How many?")
                HStack(spacing: 14) {
                    Button {
                        quantity = max(0.5, (quantity - 0.5).rounded(toPlaces: 1))
                    } label: {
                        Image(systemName: "minus")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Deck.text)
                            .frame(width: 36, height: 36)
                            .background(Deck.card, in: Circle())
                            .overlay(Circle().stroke(Deck.rule))
                    }
                    .buttonStyle(.plain)

                    VStack(spacing: 2) {
                        Text(formatted(quantity))
                            .font(.deckSerif(28))
                            .foregroundStyle(Deck.text)
                        Text("× \(formatted(servingGrams))g serving")
                            .font(.deckMono(11))
                            .foregroundStyle(Deck.muted)
                    }
                    .frame(maxWidth: .infinity)

                    Button {
                        quantity = (quantity + 0.5).rounded(toPlaces: 1)
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Deck.text)
                            .frame(width: 36, height: 36)
                            .background(Deck.card, in: Circle())
                            .overlay(Circle().stroke(Deck.rule))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 14)
                .background(Deck.card.opacity(0.5), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Deck.rule))

                HStack {
                    quickPreset("1", value: 1)
                    quickPreset("2", value: 2)
                    quickPreset("3", value: 3)
                    quickPreset("5", value: 5)
                    quickPreset("10", value: 10)
                }
            }

            Text("≈ \(formatted(totalGrams))g total · \(Int(totalKcal.rounded())) kcal")
                .font(.deckMono(11))
                .foregroundStyle(Deck.muted)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                onAdd(quantity)
            } label: {
                HStack(spacing: 8) {
                    if isAdding {
                        ProgressView().tint(Deck.ink)
                        Text("adding…")
                    } else {
                        Image(systemName: "plus")
                        Text("Add \(formatted(quantity))× to vault")
                    }
                }
                .font(.deckSans(15, weight: .medium))
                .foregroundStyle(Deck.ink)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity)
                .background(Deck.accent, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(isAdding)
        }
        .padding(.horizontal, 24)
        .padding(.top, 28)
        .padding(.bottom, 36)
        .background(
            UnevenRoundedRectangle(cornerRadii: .init(topLeading: 28, topTrailing: 28))
                .fill(Deck.bg)
                .overlay(
                    UnevenRoundedRectangle(cornerRadii: .init(topLeading: 28, topTrailing: 28))
                        .stroke(Deck.rule)
                )
        )
    }

    private func quickPreset(_ label: String, value: Double) -> some View {
        Button {
            quantity = value
        } label: {
            Text("\(label)×")
                .font(.deckMono(12))
                .foregroundStyle(quantity == value ? Deck.ink : Deck.text)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(quantity == value ? Deck.accent : .clear, in: Capsule())
                .overlay(Capsule().stroke(quantity == value ? Deck.accent : Deck.rule))
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }

    private func formatted(_ d: Double) -> String {
        if d == d.rounded() { return "\(Int(d))" }
        return String(format: "%.1f", d)
    }
}

private extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let m = pow(10.0, Double(places))
        return (self * m).rounded() / m
    }
}

private struct AddingSheet: View {
    var body: some View {
        HStack(spacing: 10) {
            ProgressView().tint(Deck.accent)
            Text("Adding to vault…")
                .font(.deckMono(12))
                .foregroundStyle(Deck.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .background(
            UnevenRoundedRectangle(cornerRadii: .init(topLeading: 28, topTrailing: 28))
                .fill(Deck.bg)
        )
    }
}

private struct AddedSheet: View {
    let item: FoodItem
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 44))
                .foregroundStyle(Deck.accent)
            Text("Added to vault")
                .font(.deckSerif(22))
                .foregroundStyle(Deck.text)
            Text(item.name)
                .font(.deckMono(12))
                .foregroundStyle(Deck.muted)

            Button(action: onDone) {
                Text("Done")
                    .font(.deckSans(15, weight: .medium))
                    .foregroundStyle(Deck.ink)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity)
                    .background(Deck.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(
            UnevenRoundedRectangle(cornerRadii: .init(topLeading: 28, topTrailing: 28))
                .fill(Deck.bg)
        )
    }
}

private struct NotFoundSheet: View {
    let code: String
    let onScanAgain: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            MonoCaption(text: "Not found", color: Deck.warning)
            Text("Couldn't find that product.")
                .font(.deckSerif(22))
                .foregroundStyle(Deck.text)
            Text(code)
                .font(.deckMono(12))
                .foregroundStyle(Deck.muted)
                .lineLimit(3)

            HStack(spacing: 10) {
                Button(action: onScanAgain) {
                    Text("Scan again")
                        .font(.deckSans(14, weight: .medium))
                        .foregroundStyle(Deck.ink)
                        .padding(.vertical, 14)
                        .frame(maxWidth: .infinity)
                        .background(Deck.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                Button(action: onDismiss) {
                    Text("Cancel")
                        .font(.deckSans(14, weight: .medium))
                        .foregroundStyle(Deck.text)
                        .padding(.vertical, 14)
                        .frame(maxWidth: .infinity)
                        .background(Deck.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Deck.rule))
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 6)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            UnevenRoundedRectangle(cornerRadii: .init(topLeading: 28, topTrailing: 28))
                .fill(Deck.bg)
        )
    }
}

private struct MacroCell: View {
    let label: String
    let value: Int
    var body: some View {
        VStack(spacing: 4) {
            Text("\(value)")
                .font(.deckSerif(20))
                .foregroundStyle(Deck.text)
            MonoCaption(text: label)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Camera permission denied overlay

private struct CameraDeniedOverlay: View {
    let onOpenSettings: () -> Void
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 14) {
                Image(systemName: "camera.fill.badge.ellipsis")
                    .font(.system(size: 48))
                    .foregroundStyle(Deck.accent)
                Text("Camera access needed")
                    .font(.deckSerif(22))
                    .foregroundStyle(.white)
                Text("DietAI needs the camera to scan barcodes. Enable it in Settings → DietAI → Camera.")
                    .font(.deckSans(13))
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 280)
                HStack(spacing: 10) {
                    Button(action: onCancel) {
                        Text("Cancel")
                            .font(.deckSans(14, weight: .medium))
                            .foregroundStyle(.white)
                            .padding(.vertical, 12)
                            .padding(.horizontal, 18)
                            .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
                    }
                    Button(action: onOpenSettings) {
                        Text("Open Settings")
                            .font(.deckSans(14, weight: .medium))
                            .foregroundStyle(Deck.ink)
                            .padding(.vertical, 12)
                            .padding(.horizontal, 18)
                            .background(Deck.accent, in: RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding(.top, 6)
            }
            .padding(24)
        }
    }
}

// Helper to nudge the simulator-only auto-fire .task to re-evaluate when stage changes.
private struct ScanIdent: Equatable {
    let stage: BarcodeViewModel.Stage
    static func == (lhs: ScanIdent, rhs: ScanIdent) -> Bool {
        switch (lhs.stage, rhs.stage) {
        case (.scanning, .scanning): return true
        case (.lookingUp, .lookingUp): return true
        case (.found, .found): return true
        case (.notFound, .notFound): return true
        case (.adding, .adding): return true
        case (.added, .added): return true
        case (.error, .error): return true
        default: return false
        }
    }
}

#Preview {
    BarcodeView()
        .preferredColorScheme(.dark)
}
