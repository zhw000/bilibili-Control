import SwiftUI

struct VideoCommentsRoute: Hashable { let bvid: String }

struct CommentsView: View {
    let bvid: String
    var root: CommentItem?
    @EnvironmentObject private var model: RemoteModel
    @State private var order = "hot"
    @State private var items: [CommentItem] = []
    @State private var nextPage: Int?
    @State private var total = 0
    @State private var loading = false
    @State private var failure: String?
    @State private var generation = UUID()
    @State private var draft = ""
    @State private var sending = false
    @State private var replyTo: CommentItem?
    @State private var receipt: String?
    @State private var sendFailure: String?

    var body: some View {
        List {
            ConnectionNotice()
            if let root { CommentRow(comment: root); Button("回复这条评论") { replyTo = root } }
            else { Picker("评论排序", selection: $order) { Text("热门评论").tag("hot"); Text("最新评论").tag("newest") }.pickerStyle(.segmented) }
            Section("\(total) 条\(root == nil ? "评论" : "回复")") {
                ForEach(items) { item in
                    VStack(alignment: .leading, spacing: 10) {
                        CommentRow(comment: item)
                        HStack {
                            Button("回复") { replyTo = item }.buttonStyle(.borderless).disabled(sending)
                            if root == nil && item.replyCount > 0 {
                                NavigationLink("查看 \(item.replyCount) 条回复") { CommentsView(bvid: bvid, root: item) }
                            }
                        }.font(.caption)
                        if root == nil {
                            ForEach(item.replies.prefix(2)) { reply in
                                Text("\(reply.creatorName)：\(reply.message)").font(.caption).foregroundStyle(.secondary).lineLimit(3)
                            }
                        }
                    }.padding(.vertical, 6)
                }
            }
            if loading { ProgressView("读取评论…") }
            if let failure { Text(failure).foregroundStyle(.secondary); Button("重试") { Task { await load(reset: false) } }.disabled(!model.ready) }
            if model.ready && !loading && failure == nil && items.isEmpty { Text("暂无\(root == nil ? "评论" : "回复")").foregroundStyle(.secondary) }
            if nextPage != nil && !loading { Button("加载更多") { Task { await load(reset: false) } }.disabled(!model.ready) }
        }.listStyle(.plain).navigationTitle(root == nil ? "视频评论" : "评论回复").navigationBarTitleDisplayMode(.inline)
            .task(id: "\(model.ready)-\(order)-\(bvid)-\(root?.id ?? "")") { await load(reset: true) }
            .refreshable { await load(reset: true) }
            .safeAreaInset(edge: .bottom) { composer }
            .alert("评论发送", isPresented: Binding(get: { receipt != nil || sendFailure != nil }, set: { if !$0 { receipt = nil; sendFailure = nil } })) {
                Button("知道了") { receipt = nil; sendFailure = nil }
            } message: { Text(receipt ?? sendFailure ?? "") }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let target = replyTo ?? root {
                HStack { Text("回复 \(target.creatorName)").font(.caption).lineLimit(1); Spacer(); if replyTo != nil { Button("取消回复") { replyTo = nil }.font(.caption).disabled(sending) } }
            }
            HStack(alignment: .bottom) {
                TextField("发表评论…", text: $draft, axis: .vertical).lineLimit(1...4).textFieldStyle(.roundedBorder).disabled(sending)
                Button { Task { await send() } } label: { if sending { ProgressView() } else { Text("发送") } }
                    .disabled(!model.ready || sending || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draft.count > 1000)
            }
            Text("\(draft.count)/1000 · 使用电脑当前登录账号发表").font(.caption2).foregroundStyle(draft.count > 1000 ? Color.red : Color.secondary)
        }.padding().background(.regularMaterial)
    }

    private func load(reset: Bool) async {
        if loading && !reset { return }
        let ticket = UUID(); generation = ticket
        guard model.ready else { loading = false; return }
        loading = true; failure = nil
        let page = reset ? 1 : nextPage ?? 1
        if reset { items = []; nextPage = nil }
        defer { if generation == ticket { loading = false } }
        var params: [String: JSONValue] = ["bvid": .string(bvid), "order": .string(order), "page": .number(Double(page))]
        if let root { params["root"] = .string(root.id) }
        do {
            let result: CommentPage = try await model.transport.request("comments.list", params: params)
            guard generation == ticket, result.bvid == bvid, !Task.isCancelled else { return }
            items.append(contentsOf: result.items.filter { item in !items.contains(where: { $0.id == item.id }) }); nextPage = result.nextPage; total = result.total
        } catch { if generation == ticket && !Task.isCancelled { failure = error.localizedDescription } }
    }

    private func send() async {
        guard !sending else { return }
        sending = true; defer { sending = false }
        var params: [String: JSONValue] = ["bvid": .string(bvid), "message": .string(draft.trimmingCharacters(in: .whitespacesAndNewlines))]
        if let thread = root ?? replyTo { params["root"] = .string(thread.id); params["parent"] = .string((replyTo ?? thread).id) }
        do {
            let result: CommentReceipt = try await model.transport.request("comments.add", params: params)
            draft = ""; replyTo = nil; receipt = result.message
            await load(reset: true)
        } catch {
            let code = (error as? RemoteFailure)?.code
            sendFailure = ["timeout", "disconnected", "browser_timeout", "browser_disconnected", "comment_uncertain"].contains(code ?? "") ? "发送结果尚未确认，请刷新评论核对后再决定是否重发。草稿已保留。" : error.localizedDescription
        }
    }
}

private struct CommentRow: View {
    let comment: CommentItem
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            CoverView(url: comment.avatar).frame(width: 34, height: 34).clipShape(Circle())
            VStack(alignment: .leading, spacing: 6) {
                NavigationLink { CreatorView(creator: CreatorItem(id: comment.creatorId, name: comment.creatorName, url: "https://space.bilibili.com/\(comment.creatorId)", avatar: comment.avatar)) } label: {
                    Text(comment.creatorName).font(.subheadline.weight(.medium))
                }.buttonStyle(.plain)
                Text(comment.message).font(.subheadline).textSelection(.enabled)
                HStack { Text(Date(timeIntervalSince1970: comment.createdAt), style: .date); Spacer(); Label("\(comment.likes)", systemImage: "hand.thumbsup") }.font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}
