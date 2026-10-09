//
//  UIApplication+Keyboard.swift
//  Chatik
//

import UIKit

extension UIApplication {
    /// Скрывает клавиатуру сразу, в том же кадре: снимает фокус с текущего поля ввода.
    /// `@FocusState` синхронизируется с этим сам. Сброс самого `@FocusState` применяется только при следующем
    /// обновлении View, поэтому клавиатура уходит с задержкой.
    func dismissKeyboard() {
        sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
