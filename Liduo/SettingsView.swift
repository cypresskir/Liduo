import SwiftUI
import AppKit

struct SettingsView: View {
    @Bindable var model: AppModel
    let controller: AppController
    @Environment(\.openWindow) private var openWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(nsImage: NSImage(named: "AppIcon") ?? NSImage())
                    .resizable().frame(width: 32, height: 32).accessibilityHidden(true)
                Text("Liduo").font(.system(size: 21, weight: .semibold, design: .rounded))
                Spacer()
                Toggle(model.preferences.enabled ? "Эффект включен" : "Эффект на паузе", isOn: $model.preferences.enabled)
                    .toggleStyle(.switch).controlSize(.small).font(.system(size: 13))
                    .accessibilityLabel("Включить эффект")
                Divider().frame(height: 20).padding(.horizontal, 8)
                Button { openWindow(id: "general") } label: {
                    Label("Настройки", systemImage: "gearshape")
                }.buttonStyle(.borderless).help("Общие настройки — ⌘,")
            }.padding(.horizontal, 24).padding(.vertical, 16)
            Divider()
            GeometryReader { geometry in
                ScrollView {
                    HStack(alignment: .top, spacing: 28) {
                        preview(width: geometry.size.width - 334)
                        inspector.frame(width: 258)
                    }.padding(24)
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func preview(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Предпросмотр").font(.system(size: 15, weight: .semibold))
                Spacer()
                Text("Пример рабочего стола").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            FoldPreview(model: model)
                .frame(width: width - 10, height: (width - 10) / 1.6)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding(5)
                .background(RoundedRectangle(cornerRadius: 15).fill(Color.black))
                .overlay(RoundedRectangle(cornerRadius: 15).strokeBorder(.primary.opacity(0.12)))
                .accessibilityLabel("Пример рабочего стола с эффектом Liduo")
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 12) {
                    Picker("Управление предпросмотром", selection: $model.previewFollowsLid) {
                        Text("Вручную").tag(false)
                        Text("Крышкой").tag(true).disabled(!model.sensorAvailable)
                    }.pickerStyle(.segmented).labelsHidden().frame(width: 190)
                        .onChange(of: model.previewFollowsLid) { _, follows in
                            if follows && !model.sensorAvailable { model.previewFollowsLid = false }
                        }
                        .onChange(of: model.sensorAvailable) { _, available in
                            if !available { model.previewFollowsLid = false }
                        }
                    Spacer(minLength: 0)
                    Text("\(model.previewFollowsLid ? "Крышка" : "В примере"): \(Int(model.previewFollowsLid ? (model.angle ?? 0) : model.previewAngle))°")
                        .font(.system(size: 12)).foregroundStyle(.secondary).monospacedDigit()
                }
                Slider(value: $model.previewAngle, in: 15...135, step: 1)
                    .disabled(model.previewFollowsLid).tint(.secondary)
                    .accessibilityLabel("Угол в примере")
                    .accessibilityValue("\(Int(model.previewFollowsLid ? (model.angle ?? 0) : model.previewAngle)) градусов")
                Text(model.previewFollowsLid ? "Прикройте крышку, чтобы увидеть эффект." : "Двигайте ползунок, чтобы посмотреть весь переход.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            Divider().padding(.vertical, 2)
            HStack(spacing: 12) {
                if model.permissionGranted {
                    Button {
                        if model.demoActive { controller.stopDemo() } else { controller.startDemo() }
                    } label: {
                        Label(model.demoActive ? "Остановить" : "Показать эффект", systemImage: model.demoActive ? "stop.fill" : "play.fill")
                            .font(.system(size: 13, weight: .medium)).padding(.horizontal, 5)
                    }.buttonStyle(.glassProminent).controlSize(.large)
                    Text(model.demoActive ? "⌘⌥B — остановить" : "На рабочем столе\n5 секунд")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                } else {
                    Button("Разрешить доступ…") { controller.requestScreenPermission() }
                        .buttonStyle(.glassProminent).controlSize(.large)
                    Text("Для эффекта\nна вашем экране")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            if let error = model.error {
                VStack(alignment: .leading, spacing: 6) {
                    Label(error, systemImage: "exclamationmark.circle").foregroundStyle(.orange)
                    Button("Проверить снова") { controller.retry() }.buttonStyle(.link)
                }.font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
            } else if model.preferences.enabled && !model.sensorAvailable {
                Label("Датчик недоступен. Можно проверить эффект кнопкой выше.", systemImage: "exclamationmark.circle")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }.frame(width: width, alignment: .leading)
    }

    private var inspector: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Стиль").font(.system(size: 15, weight: .semibold))
            HStack(spacing: 8) {
                ForEach(FoldStyle.allCases) { style in
                    Button {
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { model.select(style) }
                    } label: {
                        VStack(spacing: 8) {
                            ZStack(alignment: .bottomTrailing) {
                                if let image = StyleArtwork.image(for: style) {
                                    Image(nsImage: image).resizable().aspectRatio(1.6, contentMode: .fit)
                                } else {
                                    Rectangle().fill(.secondary.opacity(0.15)).aspectRatio(1.6, contentMode: .fit)
                                }
                                if model.preferences.style == style {
                                    Image(systemName: "checkmark.circle.fill")
                                        .symbolRenderingMode(.palette).foregroundStyle(.white, Color.accentColor)
                                        .font(.system(size: 14)).padding(4)
                                }
                            }.clipShape(RoundedRectangle(cornerRadius: 7))
                                .padding(3)
                                .overlay(RoundedRectangle(cornerRadius: 10)
                                    .strokeBorder(model.preferences.style == style ? Color.accentColor : .primary.opacity(0.12), lineWidth: model.preferences.style == style ? 2 : 1))
                            Text(style.title).font(.system(size: 12, weight: model.preferences.style == style ? .semibold : .regular))
                        }.contentShape(Rectangle())
                    }.buttonStyle(.plain)
                        .accessibilityLabel("\(style.title), \(style.subtitle.lowercased())")
                        .accessibilityAddTraits(model.preferences.style == style ? .isSelected : [])
                }
            }
            HStack(spacing: 6) {
                Text(model.preferences.style.subtitle)
                if model.preferences.hasCustomStyle { Text("· Изменен") }
            }.font(.system(size: 12)).foregroundStyle(.secondary)
            Divider()
            VStack(spacing: 16) {
                parameter("Изгиб", value: $model.preferences.perspective)
                parameter("Размытие", value: $model.preferences.blur)
                parameter("Затемнение", value: $model.preferences.shadow)
            }
            Divider()
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Text("Угол отключения")
                    Spacer()
                    Text("\(Int(model.preferences.clearAngle))°").monospacedDigit().foregroundStyle(.secondary)
                }.font(.system(size: 13))
                Slider(value: $model.preferences.clearAngle, in: 60...135, step: 1).tint(.secondary)
                    .accessibilityLabel("Угол отключения эффекта")
                    .accessibilityValue("\(Int(model.preferences.clearAngle)) градусов")
                Text("Эффект исчезает, если открыть крышку на \(Int(model.preferences.clearAngle))° или шире.")
                    .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Button("Сбросить настройки эффекта") { model.resetEffect() }
                .buttonStyle(.link).font(.system(size: 12))
                .help("Вернуть стандартный стиль, изгиб, размытие, затемнение и угол отключения. Звук и автозапуск сохранятся.")
        }
    }

    private func parameter(_ title: String, value: Binding<Double>) -> some View {
        VStack(spacing: 7) {
            HStack {
                Text(title)
                Spacer()
                Text("\(Int(value.wrappedValue * 100))%").foregroundStyle(.secondary).monospacedDigit()
            }.font(.system(size: 13))
            Slider(value: value, in: 0...1).tint(.secondary)
                .accessibilityLabel(title).accessibilityValue("\(Int(value.wrappedValue * 100)) процентов")
        }
    }
}

struct GeneralSettingsView: View {
    @Bindable var model: AppModel
    let controller: AppController
    @State private var privacyExpanded = false
    @State private var diagnosticsExpanded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(spacing: 0) {
                    settingToggle("Звук при открытии крышки", isOn: $model.preferences.sound)
                    Divider().padding(.horizontal, 16)
                    settingToggle("Запускать при входе в систему", isOn: Binding(get: { model.launchAtLogin }, set: { controller.setLaunchAtLogin($0) }))
                    Divider().padding(.horizontal, 16)
                    HStack {
                        Text("Включить или приостановить эффект")
                        Spacer()
                        Text("⌘⌥B").font(.system(size: 13, weight: .medium, design: .monospaced))
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
                    }.padding(16)
                }.settingsSurface()
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Label("Доступ к экрану", systemImage: "rectangle.inset.filled.and.person.filled")
                            .fontWeight(.medium)
                        Spacer()
                        Label(model.permissionGranted ? "Разрешен" : "Не разрешен", systemImage: model.permissionGranted ? "checkmark.circle" : "exclamationmark.circle")
                            .foregroundStyle(model.permissionGranted ? Color.secondary : .orange)
                    }
                    if !model.permissionGranted {
                        Text("Разрешите доступ, чтобы Liduo могла применить эффект к рабочему столу.")
                            .foregroundStyle(.secondary)
                        Button("Разрешить доступ…") { controller.requestScreenPermission() }.buttonStyle(.glassProminent)
                    }
                    DisclosureGroup("Как используется изображение", isExpanded: $privacyExpanded) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Изображение обрабатывается только на вашем Mac. Liduo не сохраняет снимки, не записывает звук и ничего не отправляет в интернет.")
                                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            Button("Открыть настройки macOS") { controller.openPrivacySettings() }.buttonStyle(.link)
                        }.padding(.top, 10)
                    }
                }.padding(16).settingsSurface()
                VStack(alignment: .leading, spacing: 12) {
                    DisclosureGroup("Диагностика", isExpanded: $diagnosticsExpanded) {
                        VStack(spacing: 12) {
                            detail("Угол крышки", value: model.angle.map { "\(Int($0))°" } ?? "Нет данных")
                            detail("Датчик", value: !model.preferences.enabled || model.suspended ? "Не используется" : (model.sensorAvailable ? "Подключен" : "Недоступен"))
                            detail("Эффект", value: model.status)
                            HStack { Button("Проверить снова") { controller.retry() }.buttonStyle(.link); Spacer() }
                        }.padding(.top, 12)
                    }
                    if let error = model.error { Text(error).foregroundStyle(.orange) }
                    if let error = model.hotKeyError { Text(error).foregroundStyle(.orange) }
                    if !model.sensorAvailable && model.preferences.enabled && !model.suspended {
                        Text(model.sensorDetail).foregroundStyle(.secondary)
                    }
                }.padding(16).settingsSurface()
                Text("Эффект работает только на экране MacBook. При закрытой крышке Mac засыпает как обычно.")
                    .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Text("Liduo \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }.font(.system(size: 13)).padding(24)
        }.background(Color(nsColor: .windowBackgroundColor))
    }

    private func settingToggle(_ title: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(title)
            Spacer()
            Toggle(title, isOn: isOn).labelsHidden().toggleStyle(.switch).controlSize(.small)
                .accessibilityLabel(title)
        }.padding(16)
    }

    private func detail(_ title: String, value: String) -> some View {
        HStack { Text(title).foregroundStyle(.secondary); Spacer(); Text(value).monospacedDigit() }
    }
}

private extension View {
    func settingsSurface() -> some View {
        background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
    }
}
