//
//  MessageReadersView.swift
//  Chatik
//

import SwiftUI

/// Лист «Кем прочитано»: заголовок «Прочитано: X» и список прочитавших сообщение; пока указателей нет —
/// загрузка или ошибка. Системный лист: половина экрана с раскрытием на весь экран, смахивается вниз.
struct MessageReadersView: View {
    @State private var viewModel: MessageReadersViewModel

    init(viewModel: MessageReadersViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        let content = viewModel.content
        NavigationStack {
            List(content.readers) { reader in
                MessageReaderRowView(reader: reader)
            }
            .overlay {
                if let placeholder = content.placeholder {
                    MessageReadersPlaceholderView(placeholder: placeholder)
                }
            }
            .navigationTitle(content.title)
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onAppear { viewModel.didAppear() }
        // Новый прочитавший при открытом листе тоже дозагружается, а не загрузившийся — запрашивается снова.
        .onChange(of: content, initial: true) {
            viewModel.loadMissingUsers()
        }
    }
}

/// Заглушка листа вместо пустого списка: загрузка, ошибка или «никто не прочитал».
private struct MessageReadersPlaceholderView: View {
    let placeholder: MessageReadersPlaceholder

    var body: some View {
        switch placeholder {
        case .loading:
            ProgressView()
        case .failed:
            ContentUnavailableView(MessageReadersStrings.failed, systemImage: "exclamationmark.triangle")
        case .empty:
            ContentUnavailableView(MessageReadersStrings.empty, systemImage: "eye.slash")
        }
    }
}

#if DEBUG
#Preview {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            MessageReadersView(viewModel: PreviewDependencies.messageReadersViewModel())
        }
}
#endif
