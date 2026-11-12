import SwiftUI
import AppKit
import BackstageCore

enum Filter: String, CaseIterable, Identifiable {
    case all = "전체", attention = "살펴볼 것", scheduled = "예약", resident = "상주", new = "새로 들어옴", off = "꺼짐"
    var id: String { rawValue }
}

/// "전체 보기" 창.
struct ContentView: View {
    @ObservedObject var store: Store
    @State var tab = 0

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("", selection: $tab) {
                    Text("예약·상주 작업").tag(0)
                    Text("실행 중인 프로그램").tag(1)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 300)
                Spacer()
                if store.loading { ProgressView().controlSize(.small) }
                if let u = store.updated {
                    Text("갱신 \(u.formatted(date: .omitted, time: .standard))").font(.caption).foregroundStyle(.secondary)
                }
                Button { store.refresh() } label: { Image(systemName: "arrow.clockwise") }
                    .keyboardShortcut("r")
                    .help("새로고침 (⌘R). 창이 열려 있는 동안은 30초마다 새로 읽습니다.")
            }
            .padding(.horizontal, 14).padding(.top, 12)

            if tab == 0 { JobsView(store: store) } else { ProcsView(store: store) }
        }
        .frame(minWidth: 900, minHeight: 520)
        .onReceive(store.$windowTab) { if let t = $0 { tab = t } }
    }
}

struct JobsView: View {
    @ObservedObject var store: Store
    @State private var filter: Filter = .all
    @State private var source: Source?
    @State private var query = ""

    func needsLook(_ j: Job) -> Bool {
        j.failed || !j.riskyPaths(home: store.home).isEmpty || j.ownerMissing
    }

    var filtered: [Job] {
        let q = query.trimmingCharacters(in: .whitespaces)
        return store.jobs.filter { j in
            switch filter {
            case .all: true
            case .attention: needsLook(j)
            case .scheduled: j.kind == .scheduled
            case .resident: j.kind == .resident
            case .new: store.newIDs.contains(j.id)
            case .off: !j.loaded
            }
        }
        .filter { source == nil || $0.source == source }
        .filter { j in
            q.isEmpty || j.label.localizedCaseInsensitiveContains(q)
                || j.args.joined(separator: " ").localizedCaseInsensitiveContains(q)
                || OwnerLookup.shared.info(j.owner, missing: j.ownerMissing).name.localizedCaseInsensitiveContains(q)
        }
        .sorted { a, b in
            if a.failed != b.failed { return a.failed }
            switch (a.nextRun, b.nextRun) {
            case let (x?, y?): return x < y
            case (_?, nil): return true
            case (nil, _?): return false
            default: return a.label < b.label
            }
        }
    }

    var body: some View {
        let list = filtered
        let selected = store.selection.flatMap { id in store.jobs.first { $0.id == id } }

        VStack(spacing: 10) {
            HStack {
                Picker("", selection: $filter) {
                    ForEach(Filter.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 460)
                Picker("", selection: $source) {
                    Text("모든 출처").tag(Source?.none)
                    Divider()
                    ForEach(Source.allCases, id: \.self) { Text($0.rawValue).tag(Source?.some($0)) }
                }
                .labelsHidden()
                .frame(width: 130)
                Spacer()
                Text(summaryLine).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                TextField("이름·경로·앱 검색", text: $query).textFieldStyle(.roundedBorder).frame(width: 200)
            }

            HStack(spacing: 0) {
                Table(list, selection: $store.selection) {
                    TableColumn("") { j in StatusMark(job: j, home: store.home) }.width(18)
                    TableColumn("이름") { j in
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 4) {
                                Text(j.displayProgram).fontWeight(.medium).lineLimit(1)
                                if !j.plistReadable {
                                    Image(systemName: "lock.fill").font(.caption2).foregroundStyle(.secondary)
                                        .help("설정 파일을 읽을 수 없어 일정을 알 수 없습니다")
                                }
                                if store.newIDs.contains(j.id) {
                                    Text("새 항목").font(.caption2).padding(.horizontal, 4)
                                        .background(Capsule().fill(Color.accentColor.opacity(0.18)))
                                }
                            }
                            Text(j.label).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
                                .lineLimit(1).truncationMode(.middle)
                        }
                    }.width(min: 150, ideal: 190)
                    TableColumn("출처") { j in
                        VStack(alignment: .leading, spacing: 1) {
                            OwnerLabel(job: j)
                            Text(j.source.rawValue).font(.caption).foregroundStyle(.secondary)
                        }
                    }.width(min: 100, ideal: 125)
                    TableColumn("일정") { j in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(j.schedule).lineLimit(1).help(j.schedule)
                            Text(j.kind.rawValue).font(.caption).foregroundStyle(.secondary)
                        }
                    }.width(min: 100, ideal: 135)
                    TableColumn("다음 큐") { j in
                        if let n = j.nextRun {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(timeFormatter.string(from: n))
                                Text(relative(n)).font(.caption).foregroundStyle(.secondary)
                            }
                        } else { Text("-").foregroundStyle(.secondary) }
                    }.width(min: 90, ideal: 100)
                    TableColumn("상태") { j in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(statusDescription(j.status)).lineLimit(1)
                                .foregroundStyle(j.failed ? Color.red : (j.running ? Color.green : Color.primary))
                                .help(statusDescription(j.status))
                            if let t = lastRunText(store.summaries[j.id], logChanged: store.logChanged[j.id]) {
                                Text("마지막 실행 " + t.text).font(.caption).foregroundStyle(.secondary).lineLimit(1).help(t.help)
                            }
                        }
                    }.width(min: 150, ideal: 230)
                }
                .contextMenu(forSelectionType: Job.ID.self) { ids in
                    if let j = ids.first.flatMap({ id in store.jobs.first { $0.id == id } }) { JobActions(job: j, store: store) }
                }
                .overlay {
                    if list.isEmpty {
                        Text(store.updated == nil ? "살펴보는 중…" : (store.jobs.isEmpty ? "무대 뒤가 조용합니다." : "조건에 맞는 작업이 없습니다."))
                            .foregroundStyle(.secondary)
                    }
                }

                // 고른 것이 없으면 상세 칸을 접고 표가 전체 폭을 쓴다
                if let job = selected {
                    Divider()
                    JobDetail(job: job, store: store).frame(width: 340)
                }
            }
        }
        .padding(14)
    }

    var summaryLine: String {
        let running = store.jobs.filter(\.running).count
        let look = store.jobs.filter(needsLook).count
        return "작업 \(store.jobs.count) · 실행 중 \(running)" + (look > 0 ? " · 살펴볼 것 \(look)" : "")
    }
}

/// 작업에 할 수 있는 일. 읽기 전용이라 보여 주고 복사하는 것까지만 한다.
struct JobActions: View {
    let job: Job
    @ObservedObject var store: Store

    var body: some View {
        if job.needsAttention(acknowledged: store.acknowledged) {
            Button("확인함") { store.acknowledge(job) }
            Divider()
        }
        if let p = job.plistPath {
            Button("Finder에서 설정 파일 보기") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: p)]) }
        }
        if let log = job.stderrPath ?? job.stdoutPath, !log.hasPrefix("/dev/") {
            Button("로그 열기") { NSWorkspace.shared.open(URL(fileURLWithPath: log)) }
        }
        Button("확인 명령 복사") { copy(job.inspectCommand(uid: store.uid)) }
        Button("라벨 복사") { copy(job.label) }
    }

    func copy(_ s: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
    }
}

struct JobDetail: View {
    let job: Job
    @ObservedObject var store: Store
    @State private var logText = ""

    var body: some View {
        let risky = job.riskyPaths(home: store.home)
        let summary = store.summaries[job.id]
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    StatusMark(job: job, home: store.home).padding(.top, 4)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(job.displayProgram).font(.title3.weight(.semibold)).textSelection(.enabled)
                        Text(job.label).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                    Spacer()
                    Button { store.selection = nil } label: { Image(systemName: "xmark") }
                        .buttonStyle(.borderless).help("상세 닫기")
                }

                if !risky.isEmpty {
                    note("보호 폴더(데스크탑·문서·다운로드·iCloud Drive·외장 볼륨)의 파일을 씁니다. 백그라운드(launchd) 실행에서는 macOS가 접근을 막아 '실행 불가(126)'나 'Operation not permitted'로 실패할 수 있습니다. 폴더를 ~/Projects 같은 곳으로 옮기면 해결됩니다.",
                         symbol: "exclamationmark.triangle.fill", tint: .orange)
                }
                if !job.plistReadable {
                    note("설정 파일을 읽을 권한이 없어 일정과 실행 조건은 알 수 없습니다. 상태와 실행 파일은 launchctl 이 알려 준 것입니다.",
                         symbol: "lock.fill", tint: .secondary)
                }
                if job.ownerMissing {
                    note("이 항목을 심은 앱이 지금은 그 자리에 없습니다. 앱을 지운 뒤 항목만 남은 것일 수 있습니다.",
                         symbol: "questionmark.circle.fill", tint: .secondary)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("출처").font(.caption).foregroundStyle(.secondary)
                    OwnerLabel(job: job)
                    Text(job.origin ?? job.source.rawValue).font(.caption).foregroundStyle(.secondary)
                }
                info("일정", "\(job.schedule) (\(job.kind.rawValue))")
                if let n = job.nextRun { info("다음 큐", "\(timeFormatter.string(from: n)) (\(relative(n)))") }
                info("상태", statusDescription(job.status) + (job.disabled && job.loaded ? " · 꺼 둠으로 표시됨(지금 올라와 있는 것은 그대로)" : ""))
                if let t = lastRunText(summary, logChanged: store.logChanged[job.id]) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("마지막 실행").font(.caption).foregroundStyle(.secondary)
                        Text(t.text)
                        Text(t.help).font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let s = summary, !s.recent.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("실행 기록").font(.caption).foregroundStyle(.secondary)
                        RunDots(recent: s.recent)
                        Text(recordLine(s)).font(.caption).foregroundStyle(.secondary)
                    }
                }
                if !job.args.isEmpty { info("실행 명령", job.args.joined(separator: " ")) }
                if let w = job.workingDir { info("작업 폴더", w) }
                if let p = job.plistPath { info("설정 파일", p) }

                HStack {
                    if job.needsAttention(acknowledged: store.acknowledged) {
                        Button("확인함") { store.acknowledge(job) }
                            .help("이 실패를 봤다고 표시합니다. 메뉴바 경고에서 빠지고, 다시 실패하면 다시 알려 줍니다.")
                    }
                    Menu("더 보기") { JobActions(job: job, store: store) }.fixedSize()
                }

                if job.stderrPath != nil || job.stdoutPath != nil {
                    Text("최근 로그").font(.headline)
                    Text(logText.isEmpty ? "(비어 있음 또는 읽을 수 없음)" : logText)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // 고를 때와 갱신될 때마다 다시 읽는다. 파일 읽기는 메인 밖에서.
        .task(id: "\(job.id)|\(store.updated?.timeIntervalSince1970 ?? 0)") {
            let (err, out) = (job.stderrPath, job.stdoutPath)
            let text = await Task.detached(priority: .utility) { readLogs(err: err, out: out) }.value
            if text != logText { logText = text }
        }
    }

    func recordLine(_ s: RunSummary) -> String {
        var parts = ["Backstage 가 본 실행 \(s.recent.count)회"]
        if s.failed > 0 { parts.append("실패 \(s.failed)회") }
        if let r = s.successRate { parts.append("성공률 \(r)%") }
        if s.recent.contains(where: { $0 == nil }) { parts.append("회색은 결과를 못 본 실행") }
        return parts.joined(separator: " · ")
    }

    func note(_ text: String, symbol: String, tint: Color) -> some View {
        Label { Text(text) } icon: { Image(systemName: symbol).foregroundStyle(tint) }
            .font(.callout)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(tint.opacity(0.12)))
    }

    func info(_ k: String, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(k).font(.caption).foregroundStyle(.secondary)
            Text(v).textSelection(.enabled)
        }
    }
}

func readLogs(err: String?, out: String?) -> String {
    var parts: [String] = []
    let e = tail(err, bytes: 2500)
    let o = out == err ? "" : tail(out, bytes: 2500)
    if !e.isEmpty { parts.append(out == err ? e : "[stderr]\n" + e) }
    if !o.isEmpty { parts.append("[stdout]\n" + o) }
    return parts.joined(separator: "\n\n")
}
