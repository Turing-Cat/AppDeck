#include <QCoreApplication>
#include <QClipboard>
#include <QGuiApplication>
#include <QInputMethodEvent>
#include <QKeyEvent>
#include <QMimeData>
#include <QPointer>
#include <QQuickItem>
#include <QQuickWindow>
#include <QQmlExtensionPlugin>
#include <QQmlEngine>
#include <qqml.h>
#include <memory>

// Loaded by Quickshell so the test exercises the complete AppDeck plugin.
class InputEvents : public QObject {
  Q_OBJECT
public:
  std::unique_ptr<QMimeData> clipboard;
  Q_INVOKABLE QQuickWindow *window() {
    for (auto *window : QGuiApplication::allWindows())
      if (auto *quick = qobject_cast<QQuickWindow *>(window); quick && quick->isVisible())
        return quick;
    return nullptr;
  }
  Q_INVOKABLE QObject *focus() { return window() ? window()->activeFocusItem() : nullptr; }
  Q_INVOKABLE void compose(const QString &preedit, const QString &commit = {}, bool cursorAttribute = false) {
    auto *target = window();
    if (!target) { qmlEngine(this)->throwError(QStringLiteral("No visible AppDeck window")); return; }
    QList<QInputMethodEvent::Attribute> attributes;
    if (cursorAttribute) attributes.append({QInputMethodEvent::Cursor, 0, 1, {}});
    QInputMethodEvent event(preedit, attributes);
    event.setCommitString(commit);
    QCoreApplication::sendEvent(target, &event);
  }
  Q_INVOKABLE void key(int key, int modifiers = Qt::NoModifier, const QString &text = {}) {
    QPointer<QQuickWindow> target = window();
    if (!target) { qmlEngine(this)->throwError(QStringLiteral("No visible AppDeck window")); return; }
    QKeyEvent press(QEvent::KeyPress, key, Qt::KeyboardModifiers(modifiers), text);
    QKeyEvent release(QEvent::KeyRelease, key, Qt::KeyboardModifiers(modifiers), text);
    QCoreApplication::sendEvent(target, &press);
    if (target) QCoreApplication::sendEvent(target, &release);
  }
  Q_INVOKABLE void paste(const QString &text) {
    auto *systemClipboard = QGuiApplication::clipboard();
    if (!clipboard) {
      clipboard = std::make_unique<QMimeData>();
      if (const auto *original = systemClipboard->mimeData())
        for (const auto &format : original->formats()) clipboard->setData(format, original->data(format));
    }
    systemClipboard->setText(text);
    key(Qt::Key_V, Qt::ControlModifier);
  }
  Q_INVOKABLE void finish(int code) {
    if (clipboard) QGuiApplication::clipboard()->setMimeData(clipboard.release());
    qmlEngine(this)->exit(code);
  }
};

class InputTestPlugin : public QQmlExtensionPlugin {
  Q_OBJECT
  Q_PLUGIN_METADATA(IID QQmlExtensionInterface_iid)
public:
  void registerTypes(const char *uri) override { qmlRegisterType<InputEvents>(uri, 1, 0, "InputEvents"); }
};

#include "input.test.moc"
