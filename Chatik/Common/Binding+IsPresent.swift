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
}
