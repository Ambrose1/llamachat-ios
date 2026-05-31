import SwiftUI
import LlamaKit

struct ContentView: View {
    @Bindable var viewModel: ChatViewModel

    var body: some View {
        VStack(spacing: 0) {
            statusBar
                .onAppear { viewModel.loadModel() }
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(viewModel.messages) { msg in
                            MessageBubble(message: msg)
                                .id(msg.id)
                        }
                    }
                    .padding()
                }
                .onChange(of: viewModel.messages.count) { _, _ in
                    if let last = viewModel.messages.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
                .onChange(of: viewModel.streamingText) { _, new in
                    if let last = viewModel.messages.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
            Divider()
            inputBar
        }
    }

    private var statusBar: some View {
        HStack {
            Circle()
                .fill(viewModel.isModelLoaded ? Color.green : Color.orange)
                .frame(width: 8, height: 8)
            Text(viewModel.statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            if viewModel.isGenerating {
                ProgressView()
                    .scaleEffect(0.7)
                Button("停止") {
                    viewModel.stopGeneration()
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("输入消息...", text: $viewModel.inputText)
                .textFieldStyle(.roundedBorder)
                .onSubmit { viewModel.send() }
                .disabled(!viewModel.isModelLoaded || viewModel.isGenerating)

            Button(action: viewModel.send) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
            }
            .disabled(viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .disabled(!viewModel.isModelLoaded || viewModel.isGenerating)
            .buttonStyle(.borderless)
        }
        .padding()
    }
}
