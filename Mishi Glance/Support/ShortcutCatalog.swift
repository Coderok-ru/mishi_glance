//
//  ShortcutCatalog.swift
//  Mishi Glance
//
//  Единый список клавиш. Шпаргалка и онбординг берут его отсюда, чтобы
//  подсказки не разошлись с тем, что приложение на самом деле делает.
//

import Foundation

struct ShortcutItem: Identifiable, Sendable {
    let keys: [String]
    let title: String

    var id: String { keys.joined() + title }
}

struct ShortcutGroup: Identifiable, Sendable {
    let title: String
    let symbol: String
    let items: [ShortcutItem]

    var id: String { title }
}

enum ShortcutCatalog {
    static let groups: [ShortcutGroup] = [
        ShortcutGroup(title: "Навигация", symbol: "arrow.left.arrow.right", items: [
            ShortcutItem(keys: ["←", "→"], title: "Предыдущее и следующее изображение"),
            ShortcutItem(keys: ["Space"], title: "Следующее"),
            ShortcutItem(keys: ["⇧", "Space"], title: "Предыдущее"),
            ShortcutItem(keys: ["Home", "End"], title: "Первое и последнее"),
            ShortcutItem(keys: ["Свайп"], title: "Листание двумя пальцами по трекпаду"),
            ShortcutItem(keys: ["⌘", "B"], title: "Список изображений папки"),
        ]),
        ShortcutGroup(title: "Масштаб и вид", symbol: "arrow.up.left.and.arrow.down.right", items: [
            ShortcutItem(keys: ["⌘", "0"], title: "Вписать в окно"),
            ShortcutItem(keys: ["⌘", "1"], title: "Реальный размер"),
            ShortcutItem(keys: ["⌘", "+"], title: "Увеличить"),
            ShortcutItem(keys: ["⌘", "−"], title: "Уменьшить"),
            ShortcutItem(keys: ["Пинч"], title: "Масштаб щипком, ⌘ + колесо мыши"),
            ShortcutItem(keys: ["⌘", "R"], title: "Повернуть вправо"),
            ShortcutItem(keys: ["⌘", "L"], title: "Повернуть влево"),
            ShortcutItem(keys: ["F"], title: "Во весь экран, выход — Esc"),
            ShortcutItem(keys: ["⌘", "\\"], title: "Сравнить со следующим"),
            ShortcutItem(keys: ["S"], title: "Слайдшоу, пауза — ещё раз"),
            ShortcutItem(keys: ["⌥", "⌘", "C"], title: "Пипетка: цвет под курсором"),
        ]),
        ShortcutGroup(title: "Отбор кадров", symbol: "checkmark.circle", items: [
            ShortcutItem(keys: ["P"], title: "Отобрать"),
            ShortcutItem(keys: ["X"], title: "Отклонить"),
            ShortcutItem(keys: ["U"], title: "Снять пометку"),
            ShortcutItem(keys: ["1", "…", "5"], title: "Рейтинг звёздами"),
            ShortcutItem(keys: ["0"], title: "Убрать рейтинг"),
        ]),
        ShortcutGroup(title: "Файл", symbol: "doc", items: [
            ShortcutItem(keys: ["⌘", "I"], title: "Сведения о снимке"),
            ShortcutItem(keys: ["⌘", "C"], title: "Скопировать изображение"),
            ShortcutItem(keys: ["⇧", "⌘", "E"], title: "Экспорт и конвертация"),
            ShortcutItem(keys: ["⌘", "E"], title: "Открыть во внешнем редакторе"),
            ShortcutItem(keys: ["⇧", "⌘", "R"], title: "Показать в Finder"),
            ShortcutItem(keys: ["⌘", "⌫"], title: "Переместить в Корзину"),
            ShortcutItem(keys: ["⌘", "O"], title: "Открыть файл или папку"),
            ShortcutItem(keys: ["⌘", "P"], title: "Напечатать"),
        ]),
    ]

    /// Самое нужное для первого знакомства.
    static let essentials: [ShortcutItem] = [
        ShortcutItem(keys: ["←", "→"], title: "Листать всю папку"),
        ShortcutItem(keys: ["F"], title: "Во весь экран"),
        ShortcutItem(keys: ["⌘", "I"], title: "Сведения о снимке"),
        ShortcutItem(keys: ["P", "X"], title: "Отобрать или отклонить"),
    ]
}
