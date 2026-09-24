import SwiftUI
import OnyxCore
import OnyxData
import OnyxUI
#if canImport(VisionKit)
import VisionKit
#endif

/// "Add from label database" (overhaul C3, decision Q11): search the NIH DSLD
/// by PRODUCT or by BRAND, read one label, and hand the stack's edit sheet a
/// prefilled item — name, form, dose and per-unit micronutrients.
///
/// ── THE MANUAL PATH IS NEVER BEHIND THIS ────────────────────────────────────
/// Every failure — offline, a timeout after three retries, a label that will
/// not decode — is one line of notice and an "Add by hand" button that opens
/// the ordinary sheet with whatever was typed as the name. The founder may not
/// have the bottle yet, so the barcode is OPTIONAL and hidden where the camera
/// cannot scan.
///
/// Speed: a 300 ms debounce, and `.task(id:)` cancels the request a newer
/// keystroke superseded. The client caches every answer for a week.
struct DSLDImportView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case product = "Product", brand = "Brand"
        var id: String { rawValue }
    }

    /// Hands the prefill back; the presenter opens the edit sheet.
    let onAdd: (DSLD.Prefill) -> Void
    /// The manual path, with whatever name was typed.
    let onManual: (String) -> Void
    var client = DSLDClient()
    /// Harness only: results and a label to show without the network.
    var seed: Seed? = nil

    struct Seed {
        var query: String
        var mode: Mode = .product
        var hits: [DSLD.Hit]
        var label: DSLD.Label?
    }

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var mode: Mode = .product
    @State private var hits: [DSLD.Hit] = []
    @State private var brands: [String] = []
    @State private var brand: String?
    @State private var total = 0
    @State private var loading = false
    @State private var failed = false
    @State private var opened: DSLD.Hit?
    @State private var scanning = false
    @State private var seeded = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Search by", selection: $mode) {
                        ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                }
                if failed { notice }
                if let brand { brandHeader(brand) }
                results
            }
            .scrollContentBackground(.hidden)
            .onyxScreen(.fuel)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: mode == .product ? "Product, e.g. magnesium glycinate" : "Brand, e.g. Thorne")
            .navigationTitle("Label database")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                if Self.canScan {
                    ToolbarItem(placement: .primaryAction) {
                        Button { scanning = true } label: { Image(systemName: "barcode.viewfinder") }
                            .accessibilityLabel("Scan a barcode")
                    }
                }
            }
            .navigationDestination(item: $opened) { hit in
                DSLDLabelView(hit: hit, client: client, seeded: seed?.label, onAdd: onAdd, onManual: onManual)
            }
            .task(id: "\(mode.rawValue)|\(query)|\(brand ?? "")") { await search() }
            .onChange(of: mode) { _, _ in brand = nil }
            .sheet(isPresented: $scanning) { scanner }
        }
        .onAppear(perform: applySeed)
    }

    // MARK: - Rows

    @ViewBuilder
    private var results: some View {
        if mode == .brand, brand == nil {
            ForEach(brands, id: \.self) { name in
                Button { brand = name } label: {
                    HStack {
                        Text(name).onyxType(.body).foregroundStyle(Color.onyx.textPrimary)
                        Spacer()
                        Image(systemName: "chevron.right").onyxType(.caption).foregroundStyle(Color.onyx.textTertiary)
                    }
                }
            }
        } else {
            ForEach(hits) { hit in
                Button { opened = hit } label: { row(hit) }
            }
            if hits.count < total, !loading {
                Button("Show more") { Task { await search(more: true) } }
                    .foregroundStyle(Color.onyx.accent(.fuel))
            }
        }
        if loading {
            HStack { Spacer(); ProgressView(); Spacer() }
                .listRowBackground(Color.clear)
        } else if !failed, !query.trimmingCharacters(in: .whitespaces).isEmpty,
                  hits.isEmpty, brands.isEmpty {
            Text("Nothing on the label database by that name.")
                .onyxType(.caption).foregroundStyle(Color.onyx.textSecondary)
                .listRowBackground(Color.clear)
        }
    }

    /// `Thorne · Basic Nutrients 2/Day · Capsule`.
    private func row(_ hit: DSLD.Hit) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(hit.product)
                .onyxType(.body).foregroundStyle(Color.onyx.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text([hit.brand, hit.serving ?? hit.form].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                .onyxType(.caption).foregroundStyle(Color.onyx.textSecondary)
            if hit.offMarket {
                Text("Off the market").onyxType(.micro).foregroundStyle(Color.onyx.textTertiary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private func brandHeader(_ name: String) -> some View {
        Button { brand = nil } label: {
            Label("All brands · \(name)", systemImage: "chevron.left")
                .onyxType(.caption)
                .foregroundStyle(Color.onyx.accent(.fuel))
        }
        .listRowBackground(Color.clear)
    }

    private var notice: some View {
        VStack(alignment: .leading, spacing: OnyxSpace.s) {
            Label("The label database is unreachable — add it by hand.", systemImage: "wifi.exclamationmark")
                .onyxType(.caption)
                .foregroundStyle(Color.onyx.textSecondary)
            Button("Add by hand") {
                onManual(query.trimmingCharacters(in: .whitespaces))
            }
            .buttonStyle(.bordered)
            .tint(Color.onyx.accent(.fuel))
        }
    }

    // MARK: - Search

    private func applySeed() {
        guard let seed, !seeded else { return }
        seeded = true
        query = seed.query
        mode = seed.mode
        hits = seed.hits
        total = seed.hits.count
        if let label = seed.label, let hit = seed.hits.first(where: { $0.id == String(label.id) }) {
            opened = hit
        }
    }

    private func search(more: Bool = false) async {
        guard seed == nil else { return }
        let text = query.trimmingCharacters(in: .whitespaces)
        guard text.count >= 2 || brand != nil else {
            hits = []; brands = []; failed = false
            return
        }
        if !more {
            // The debounce: a newer keystroke cancels this task before it asks.
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
        }
        loading = true
        defer { loading = false }
        do {
            if mode == .brand, brand == nil {
                brands = try await client.brands(text)
                hits = []
            } else {
                let offset = more ? hits.count : 0
                let page: DSLD.Page
                if let brand {
                    page = try await client.products(brand: brand, from: offset)
                } else {
                    page = try await client.searchProducts(text, from: offset)
                }
                hits = more ? hits + page.hits : page.hits
                total = page.total
            }
            failed = false
        } catch is CancellationError {
            return
        } catch let error as URLError where error.code == .cancelled {
            return
        } catch {
            failed = true
        }
    }

    // MARK: - Barcode (optional)

    static var canScan: Bool {
        #if canImport(VisionKit)
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
        #else
        false
        #endif
    }

    @ViewBuilder
    private var scanner: some View {
        #if canImport(VisionKit)
        BarcodeScanner { code in
            scanning = false
            Task {
                // Barcode → a name through Open Food Facts → a product search.
                // A code OFF does not know leaves the digits for the reader.
                let name = try? await client.productName(barcode: code)
                mode = .product
                brand = nil
                query = name ?? code
            }
        }
        .ignoresSafeArea()
        #endif
    }
}

#if canImport(VisionKit)
/// VisionKit's scanner, barcodes only; the first one read closes it.
private struct BarcodeScanner: UIViewControllerRepresentable {
    let onCode: (String) -> Void

    func makeUIViewController(context: UIViewControllerRepresentableContext<BarcodeScanner>) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode()], qualityLevel: .balanced,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        try? scanner.startScanning()
        return scanner
    }

    func updateUIViewController(_ controller: DataScannerViewController, context: UIViewControllerRepresentableContext<BarcodeScanner>) {}

    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode) }

    @MainActor
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onCode: (String) -> Void
        private var done = false
        init(onCode: @escaping (String) -> Void) { self.onCode = onCode }

        func dataScanner(_ scanner: DataScannerViewController, didAdd items: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !done else { return }
            for item in items {
                if case .barcode(let code) = item, let value = code.payloadStringValue {
                    done = true
                    scanner.stopScanning()
                    onCode(value)
                    return
                }
            }
        }
    }
}
#endif

/// One label: what the sheet will be filled with, row by row.
struct DSLDLabelView: View {
    let hit: DSLD.Hit
    let client: DSLDClient
    var seeded: DSLD.Label? = nil
    let onAdd: (DSLD.Prefill) -> Void
    let onManual: (String) -> Void

    @State private var label: DSLD.Label?
    @State private var failed = false

    var body: some View {
        List {
            if let label {
                let prefill = DSLD.prefill(label)
                Section {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(label.fullName).onyxType(.display).foregroundStyle(Color.onyx.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text([label.brandName, label.servingSizes.first?.text.map { "serving \($0)" }]
                            .compactMap { $0 }.joined(separator: " · "))
                            .onyxType(.caption).foregroundStyle(Color.onyx.textSecondary)
                    }
                }
                Section {
                    ForEach(Array(label.ingredientRows.enumerated()), id: \.offset) { _, row in
                        ingredient(row, mapped: DSLD.nutrientKey(row.name).map { prefill.micros[$0] != nil } ?? false)
                    }
                } header: {
                    Text("Per serving").onyxType(.micro).textCase(.uppercase)
                        .foregroundStyle(Color.onyx.textTertiary)
                } footer: {
                    Text("\(prefill.micros.count) of \(label.ingredientRows.count) count toward your micronutrients; the rest are kept on the item by name.")
                        .onyxType(.caption)
                }
            } else if failed {
                VStack(alignment: .leading, spacing: OnyxSpace.s) {
                    Label("This label could not be read — add it by hand.", systemImage: "wifi.exclamationmark")
                        .onyxType(.caption).foregroundStyle(Color.onyx.textSecondary)
                    Button("Add by hand") { onManual("\(hit.brand) \(hit.product)") }
                        .buttonStyle(.bordered).tint(Color.onyx.accent(.fuel))
                }
            } else {
                HStack { Spacer(); ProgressView(); Spacer() }.listRowBackground(Color.clear)
            }
        }
        .scrollContentBackground(.hidden)
        .onyxScreen(.fuel)
        .navigationTitle(hit.brand)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Add") { if let label { onAdd(DSLD.prefill(label)) } }
                    .disabled(label == nil)
                    .fontWeight(.semibold)
            }
        }
        .task {
            if let seeded { label = seeded; return }
            do { label = try await client.label(id: hit.id) } catch { failed = true }
        }
    }

    /// Name · amount unit · %DV, and a dot when it counts toward the micros.
    private func ingredient(_ row: DSLD.Label.IngredientRow, mapped: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: OnyxSpace.s) {
            Circle()
                .fill(mapped ? Color.onyx.accent(.fuel) : Color.clear)
                .frame(width: 6, height: 6)
                .accessibilityHidden(true)
            Text(row.name).onyxType(.body).foregroundStyle(Color.onyx.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: OnyxSpace.s)
            Text([row.amount.map(Self.number), row.unit].compactMap { $0 }.joined(separator: " "))
                .onyxType(.caption).onyxNumeral().foregroundStyle(Color.onyx.textSecondary)
            if let dv = row.percentDV {
                Text("\(Self.number(dv))%")
                    .onyxType(.caption).onyxNumeral().foregroundStyle(Color.onyx.textTertiary)
                    .frame(minWidth: 44, alignment: .trailing)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint(mapped ? "Counts toward your micronutrients" : "Kept by name")
    }

    static func number(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(format: "%g", v)
    }
}
