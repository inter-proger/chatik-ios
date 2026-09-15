//
//  Binding+IsPresent.swift
//  Chatik
//

import SwiftUI

extension Binding {
    /// Превращает binding к опционалу в `Binding<Bool>` для `.alert(isPresented:)`:
    /// `true`, пока значение не `nil`; установка в `false` обнуляет значение.
    func isPresent<T>() -> Binding<Bool> where Value == T? {
        Binding<Bool>(
            get: { wrappedValue != nil },
            set: { isPresented in
                guard !isPresented else { return }
                wrappedValue = nil
            }
        )
    }

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
