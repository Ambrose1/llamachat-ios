import SwiftUI

// MARK: - Types

struct ChatMessage: Identifiable {
    let id = UUID()
    let role: MessageRole
    var content: String

    enum MessageRole {
        case user
        case assistant
    }
}

// MARK: - Views

struct ChatBubbleView: View {
    let message: ChatMessage

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if message.role == .assistant {
                avatar(for: .assistant)
                bubbleContent
                Spacer(minLength: 50)
            } else {
                Spacer(minLength: 50)
                bubbleContent
                avatar(for: .user)
            }
        }
        .padding(.horizontal, 4)
    }

    @ViewBuilder
    private func avatar(for role: ChatMessage.MessageRole) -> some View {
        Group {
            if role == .assistant {
                Image(systemName: "brain.head.profile")
                    .font(.body)
                    .frame(width: 28, height: 28)
                    .background(Color.indigo.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                Image(systemName: "person.circle.fill")
                    .font(.title3)
                    .frame(width: 28, height: 28)
                    .foregroundStyle(.blue)
            }
        }
    }

    private var bubbleContent: some View {
        Text(message.content)
            .font(.body)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(message.role == .user ? Color.blue.opacity(0.1) : Color.indigo.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
