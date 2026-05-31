import SwiftUI

enum MessageRole: String, Codable {
    case user
    case assistant
}

struct ChatMessage: Identifiable, Codable {
    let id = UUID()
    let role: MessageRole
    var content: String
}

struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if message.role == .assistant {
                avatarView(role: .assistant)
                messageContent
                Spacer(minLength: 40)
            } else {
                Spacer(minLength: 40)
                messageContent
                avatarView(role: .user)
            }
        }
    }

    @ViewBuilder
    private func avatarView(role: MessageRole) -> some View {
        Group {
            if role == .assistant {
                Image(systemName: "brain.head.profile")
                    .font(.title3)
                    .frame(width: 32, height: 32)
                    .background(Color.indigo.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                Image(systemName: "person.circle.fill")
                    .font(.title3)
                    .frame(width: 32, height: 32)
                    .foregroundStyle(.blue)
            }
        }
    }

    private var messageContent: some View {
        Text(message.content)
            .font(.body)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(message.role == .user ? Color.blue.opacity(0.1) : Color.indigo.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .textSelection(.enabled)
    }
}
