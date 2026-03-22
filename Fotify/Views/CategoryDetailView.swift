import SwiftUI
import Photos
import Vision

struct CategoryDetailView: View {
    let category: PhotoCategory
    let onBack: () -> Void
    @EnvironmentObject var photoLibrary: PhotoLibraryService
    @State private var assets: [PHAsset] = []
    @State private var isLoading = true
    @State private var scanProgress: Double = 0

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 3)

    /// Categories that need Vision scanning instead of simple fetch
    private var needsVisionScan: Bool {
        category == .people || category == .documents
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.title3.bold())
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(.ultraThinMaterial.opacity(0.5))
                        .clipShape(Circle())
                }

                Image(systemName: category.icon)
                    .font(.title3)
                    .foregroundStyle(category.color)

                VStack(alignment: .leading, spacing: 2) {
                    Text(category.label.uppercased())
                        .font(.caption.bold())
                        .kerning(2)
                        .foregroundStyle(category.color)
                    if isLoading && needsVisionScan {
                        Text("Escaneando... \(Int(scanProgress * 100))%")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("\(assets.count) elementos")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            // Content
            if isLoading {
                Spacer()
                VStack(spacing: 16) {
                    if needsVisionScan {
                        // Scan progress
                        ZStack {
                            Circle()
                                .stroke(Color.white.opacity(0.1), lineWidth: 3)
                                .frame(width: 100, height: 100)
                            Circle()
                                .trim(from: 0, to: scanProgress)
                                .stroke(category.color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                                .frame(width: 100, height: 100)
                                .rotationEffect(.degrees(-90))
                            VStack(spacing: 2) {
                                Image(systemName: category.icon)
                                    .font(.title2)
                                    .foregroundStyle(category.color)
                                Text("\(Int(scanProgress * 100))%")
                                    .font(.caption2.bold())
                                    .foregroundStyle(.white)
                            }
                        }
                        Text("Analizando fotos con Vision...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        // Show results as they come in
                        if !assets.isEmpty {
                            Text("\(assets.count) encontradas")
                                .font(.caption2)
                                .foregroundStyle(category.color)
                        }
                    } else {
                        ProgressView("Cargando \(category.label.lowercased())...")
                            .tint(.white)
                    }
                }
                Spacer()
            } else if assets.isEmpty {
                Spacer()
                VStack(spacing: 16) {
                    Image(systemName: category.icon)
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("Sin \(category.label.lowercased()) disponibles")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVGrid(columns: columns, spacing: 4) {
                        ForEach(0..<assets.count, id: \.self) { index in
                            CategoryPhotoCell(asset: assets[index])
                        }
                    }
                    .padding(.horizontal, 4)
                }
            }
        }
        .task {
            await loadAssets()
        }
    }

    private func loadAssets() async {
        switch category {
        case .people:
            await scanWithVision(detectFaces: true)
        case .documents:
            await scanWithVision(detectFaces: false)
        default:
            assets = photoLibrary.assets(for: category)
            isLoading = false
        }
    }

    /// Scans photos using Vision framework for faces or text/documents
    private func scanWithVision(detectFaces: Bool) async {
        guard let allPhotos = photoLibrary.allPhotos else {
            isLoading = false
            return
        }

        let totalCount = min(allPhotos.count, 500)
        var found: [PHAsset] = []

        for i in 0..<totalCount {
            let asset = allPhotos.object(at: i)

            if let image = await photoLibrary.thumbnail(for: asset, size: CGSize(width: 300, height: 300)),
               let cgImage = image.cgImage {

                let matches: Bool
                if detectFaces {
                    matches = await detectFacesInImage(cgImage)
                } else {
                    matches = await detectTextInImage(cgImage)
                }

                if matches {
                    found.append(asset)
                    assets = found
                }
            }

            scanProgress = Double(i + 1) / Double(totalCount)
        }

        assets = found
        isLoading = false
    }

    /// Detects faces using VNDetectFaceRectanglesRequest
    private func detectFacesInImage(_ cgImage: CGImage) async -> Bool {
        await withCheckedContinuation { continuation in
            let request = VNDetectFaceRectanglesRequest { request, _ in
                let faceCount = (request.results as? [VNFaceObservation])?.count ?? 0
                continuation.resume(returning: faceCount > 0)
            }
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: false)
            }
        }
    }

    /// Detects text/documents using VNDetectTextRectanglesRequest
    private func detectTextInImage(_ cgImage: CGImage) async -> Bool {
        await withCheckedContinuation { continuation in
            let request = VNDetectTextRectanglesRequest { request, _ in
                let textRegions = (request.results as? [VNTextObservation])?.count ?? 0
                // Consider it a "document" if it has 3+ text regions
                continuation.resume(returning: textRegions >= 3)
            }
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(returning: false)
            }
        }
    }
}

// MARK: - Category Photo Cell

struct CategoryPhotoCell: View {
    let asset: PHAsset
    @EnvironmentObject var photoLibrary: PhotoLibraryService
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle()
                    .fill(.gray.opacity(0.2))
                    .overlay {
                        ProgressView().tint(.white).scaleEffect(0.7)
                    }
            }
        }
        .aspectRatio(1, contentMode: .fill)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .task(id: asset.localIdentifier) {
            image = await photoLibrary.thumbnail(for: asset, size: CGSize(width: 300, height: 300))
        }
    }
}
