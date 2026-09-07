//
//  SettingsView.swift
//  Mishi Glance
//

import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("Общие", systemImage: "gearshape") }
            ViewingSettingsView()
                .tabItem { Label("Просмотр", systemImage: "photo") }
            FileTypesSettingsView()
                .tabItem { Label("Типы файлов", systemImage: "doc.badge.gearshape") }
        }
        .frame(width: 540, height: 520)
    }
}

/// Tells every open viewer to re-read preferences that affect rendering.
func notifyViewersOfSettingsChange() {
    NotificationCenter.default.post(name: .viewerSettingsChanged, object: nil)
}
