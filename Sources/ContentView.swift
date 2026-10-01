import SwiftUI

struct FileItem: Identifiable {
    let id = UUID()
    let name: String
    let date: Date
    let size: Int64
    let url: URL
    
    // 格式化檔案大小（例：1.2 MB、350 KB）
    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
    
    // 格式化日期時間（例：2026/10/01 18:30）
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

struct ContentView: View {
    @State private var fileList: [FileItem] = []

    var body: some View {
        NavigationStack {
            List {
                ForEach(fileList) { item in
                    HStack(spacing: 12) {
                        // 原生通用檔案圖示（不顯示圖片縮圖）
                        Image(systemName: "doc")
                            .font(.title2)
                            .foregroundStyle(.blue)
                            .frame(width: 32, height: 32)

                        VStack(alignment: .leading, spacing: 4) {
                            // 檔名
                            Text(item.name)
                                .font(.body)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            
                            // 下方灰字：日期與檔案大小（格式參考 iOS 檔案 App）
                            HStack(spacing: 6) {
                                Text(item.formattedDate)
                                Text("•")
                                Text(item.formattedSize)
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                    // 點擊項目時不做任何開啟動作
                    .contentShape(Rectangle())
                    .onTapGesture {
                        // 點擊打不開
                    }
                }
            }
            .listStyle(.plain)
            .navigationTitle("TraceViewer")
            .navigationBarTitleDisplayMode(.large) // 大標題、置左
            .onAppear(perform: loadLibraryFiles)
            .refreshable {
                loadLibraryFiles()
            }
        }
    }

    // 讀取 App 自己的 Library 目錄內容
    private func loadLibraryFiles() {
        let fileManager = FileManager.default
        guard let libraryURL = fileManager.urls(for: .libraryDirectory, in: .userDomainMask).first else { return }

        do {
            let fileURLs = try fileManager.contentsOfDirectory(
                at: libraryURL,
                includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey, .isDirectoryKey],
                options: [.skipsHiddenFiles]
            )

            var items: [FileItem] = []

            for url in fileURLs {
                let resourceValues = try url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey, .isDirectoryKey])
                
                // 只讀取檔案，排除資料夾
                if resourceValues.isDirectory != true {
                    let name = url.lastPathComponent
                    let date = resourceValues.contentModificationDate ?? Date.distantPast
                    let size = Int64(resourceValues.fileSize ?? 0)

                    items.append(FileItem(name: name, date: date, size: size, url: url))
                }
            }

            // 由新至舊排序（最新修改的在最上面）
            self.fileList = items.sorted(by: { $0.date > $1.date })

        } catch {
            print("讀取 Library 目錄失敗: \(error.localizedDescription)")
        }
    }
}

#Preview {
    ContentView()
}
