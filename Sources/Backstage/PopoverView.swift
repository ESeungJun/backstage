import SwiftUI
import AppKit
import BackstageCore

/// 메뉴바 아이콘을 누르면 내려오는 요약. 볼 일이 있는 것만 보여 주고, 나머지는 "전체 보기" 창에 있다.
struct PopoverView: View {
    @ObservedObject var store: Store
    @ObservedObject var login: LoginItem
    @ObservedObject var notifier: Notifier
    var openWindow: (Job.ID?) -> Void = { _ in }
    var openProcs: () -> Void = {}

    static let size = CGSize(width: 420, height: 520)

    var body: some View {
        let attention = store.attention
        let arrivals = store.jobs.filter { store.newIDs.contains($0.id) }
        let cues = store.jobs.filter { $0.nextRun != nil && $0.loaded }.sorted { $0.nextRun! < $1.nextRun! }.prefix(3)
        let running = store.jobs.filter(\.running)

        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text("Backstage").font(.headline)
                Text("무대 뒤 \(store.jobs.count)개").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if store.loading { ProgressView().controlSize(.small) }
                if let u = store.updated {
                    Text("갱신 \(u.formatted(date: .omitted, time: .shortened))").font(.caption).foregroundStyle(.secondary)
                }
                Button { store.refresh() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless)
                    .keyboardShortcut("r")
                    .help("새로고침 (⌘R)")
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if login.shouldAsk {
                        HStack {
                            Text("로그인할 때 Backstage를 자동으로 켤까요?").font(.callout)
                            Spacer()
                            Button("켜기") { login.set(true) }
                            Button("나중에") { login.answered() }
                        }
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
                    }

                    section("살펴볼 것", count: attention.count) {
                        if attention.isEmpty {
                            quiet(store.updated == nil ? "살펴보는 중…" : "실패한 내 작업이 없어요.")
                        } else {
                            ForEach(attention) { j in
                                row(j, sub: j.lastExit.map(exitDescription) ?? j.label) {
                                    Button("확인함") { store.acknowledge(j) }
                                        .controlSize(.small)
                                        .help("봤다고 표시해요. 또 실패하면 다시 알려 줘요.")
                                }
                            }
                        }
                    }

                    section("CPU 제일 많이 쓰는 앱", count: nil) {
                        BusiestCard(store: store, open: openProcs)
                    }

                    if !arrivals.isEmpty {
                        section("새로 들어온 항목", count: arrivals.count) {
                            ForEach(arrivals.prefix(5)) { j in
                                row(j, sub: "\(OwnerLookup.shared.info(j.owner, missing: j.ownerMissing).name) · \(j.source.rawValue)") { EmptyView() }
                            }
                        }
                    }

                    section("다음 큐", count: nil) {
                        if cues.isEmpty { quiet("예정된 실행이 없어요.") }
                        ForEach(Array(cues)) { j in
                            row(j, sub: j.schedule) {
                                VStack(alignment: .trailing, spacing: 1) {
                                    Text(timeFormatter.string(from: j.nextRun!)).font(.callout)
                                    Text(relative(j.nextRun!)).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }

                    section("지금 무대 위", count: running.count) {
                        if running.isEmpty { quiet("무대 뒤가 조용해요.") }
                        else {
                            Text(running.prefix(12).map(\.displayProgram).joined(separator: " · ")
                                 + (running.count > 12 ? " 외 \(running.count - 12)개" : ""))
                                .font(.callout).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()
            HStack {
                Button("전체 보기") { openWindow(nil) }
                    .keyboardShortcut("o")
                    .help("모든 작업을 창으로 열어요 (⌘O)")
                Spacer()
                Menu {
                    Toggle("로그인 시 실행", isOn: Binding(get: { login.enabled }, set: { login.set($0) }))
                    Toggle("새 항목이 생기면 알림", isOn: Binding(get: { notifier.enabled }, set: { notifier.set($0) }))
                    Divider()
                    Text("Backstage \(appVersion)")
                    Button("Backstage 종료") { NSApplication.shared.terminate(nil) }
                        .keyboardShortcut("q")
                } label: { Image(systemName: "ellipsis.circle") }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help(login.error ?? notifier.error ?? "설정")
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
        }
        .frame(width: PopoverView.size.width, height: PopoverView.size.height)
    }

    func section<Content: View>(_ title: String, count: Int?, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text(title).font(.subheadline.weight(.semibold))
                if let count, count > 0 { Text("\(count)").font(.subheadline).foregroundStyle(.secondary) }
            }
            content()
        }
    }

    func quiet(_ text: String) -> some View {
        Text(text).font(.callout).foregroundStyle(.secondary)
    }

    func row<Trailing: View>(_ j: Job, sub: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(alignment: .center, spacing: 8) {
            StatusMark(job: j, home: store.home)
            Button { openWindow(j.id) } label: {
                VStack(alignment: .leading, spacing: 1) {
                    Text(j.displayProgram).fontWeight(.medium).lineLimit(1)
                    Text(sub).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("\(j.label) · 전체 보기에서 열기")
            trailing()
        }
    }
}
