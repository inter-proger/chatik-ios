//
//  Binding+IsPresent.swift
//  Chatik
//

import SwiftUI

extension Binding {
    /// `Binding<Bool>` для показа одного из нескольких экранов по значению опционала:
    /// `true`, пока значение равно `value`; установка в `false` обнуляет значение.
    /// - Parameter value: вариант, при котором экран показан.
    func isPresent<T: Equatable>(_ value: T) -> Binding<Bool> where Value == T? {
        Binding<Bool>(
            get: { wrappedValue == value },
            set: { isPresented in
                guard !isPresented else { return }
                wrappedValue = nil
            }
        )
    }
}
